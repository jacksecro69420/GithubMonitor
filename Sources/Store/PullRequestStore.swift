import AppKit
import Foundation
import Observation

enum FeedMode: String, CaseIterable, Identifiable {
    case pullRequests
    case issues

    var id: String {
        rawValue
    }

    var title: String {
        switch self {
        case .pullRequests:
            return "PRs"
        case .issues:
            return "Issues"
        }
    }

    var heading: String {
        switch self {
        case .pullRequests:
            return "Open Pull Requests"
        case .issues:
            return "Open Issues"
        }
    }
}

enum SessionState {
    case missingClientID
    case signedOut
    case awaitingAuthorization(DeviceAuthorization)
    case signedIn
}

@MainActor
@Observable
final class PullRequestStore {
    private let menuOpenRefreshMinimumInterval: TimeInterval = 20

    private let config: AppConfig
    private let oauthClient: GitHubOAuthDeviceClient
    private let apiClient: GitHubAPIClient
    private let tokenStore: TokenStore

    private var accessToken: String?
    private var hasRestoredSession = false
    private var authorizationTask: Task<Void, Never>?

    private(set) var sessionState: SessionState = .signedOut
    private(set) var currentUser: String?
    private(set) var selectedFeedMode: FeedMode = .pullRequests
    private(set) var pullRequests: [PullRequest] = []
    private(set) var issues: [Issue] = []
    private(set) var selectedRepositoryFilter: String?
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastRefreshedAt: Date?

    var recentRepositoryFilters: [String] {
        let latestByRepo = Dictionary(grouping: activeFeedRepositoryItems, by: \.repositoryNameWithOwner)
            .compactMap { repository, items -> (String, Date)? in
                guard let latestDate = items.map(\.updatedAt).max() else {
                    return nil
                }
                return (repository, latestDate)
            }
            .sorted { lhs, rhs in
                lhs.1 > rhs.1
            }

        return Array(latestByRepo.map(\.0).prefix(12))
    }

    var filteredPullRequests: [PullRequest] {
        let base: [PullRequest]
        if let selectedRepositoryFilter, !selectedRepositoryFilter.isEmpty {
            base = pullRequests.filter { $0.repositoryNameWithOwner == selectedRepositoryFilter }
        } else {
            base = pullRequests
        }

        return base.sorted { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }
    }

    var filteredIssues: [Issue] {
        let base: [Issue]
        if let selectedRepositoryFilter, !selectedRepositoryFilter.isEmpty {
            base = issues.filter { $0.repositoryNameWithOwner == selectedRepositoryFilter }
        } else {
            base = issues
        }

        return base.sorted { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }
    }

    var filteredItemCount: Int {
        switch selectedFeedMode {
        case .pullRequests:
            return filteredPullRequests.count
        case .issues:
            return filteredIssues.count
        }
    }

    var isSelectedFeedEmpty: Bool {
        switch selectedFeedMode {
        case .pullRequests:
            return pullRequests.isEmpty
        case .issues:
            return issues.isEmpty
        }
    }

    var selectedFeedHeading: String {
        selectedFeedMode.heading
    }

    init(
        config: AppConfig = AppConfig(),
        oauthClient: GitHubOAuthDeviceClient = GitHubOAuthDeviceClient(),
        apiClient: GitHubAPIClient = GitHubAPIClient(),
        tokenStore: TokenStore = KeychainTokenStore()
    ) {
        self.config = config
        self.oauthClient = oauthClient
        self.apiClient = apiClient
        self.tokenStore = tokenStore
    }

    func restoreSessionIfNeeded() async {
        guard !hasRestoredSession else {
            return
        }
        hasRestoredSession = true

        guard config.hasClientID else {
            sessionState = .missingClientID
            errorMessage = "Set GitHubOAuthClientID in Project.swift Info.plist or GITHUB_CLIENT_ID in your environment."
            return
        }

        do {
            if let token = try tokenStore.readToken(), !token.isEmpty {
                accessToken = token
                sessionState = .signedIn
                await refresh()
            } else {
                sessionState = .signedOut
            }
        } catch {
            sessionState = .signedOut
            errorMessage = "Failed to read saved login token."
        }
    }

    func beginDeviceLogin() async {
        guard config.hasClientID else {
            sessionState = .missingClientID
            errorMessage = "Missing OAuth client ID."
            return
        }

        authorizationTask?.cancel()
        errorMessage = nil
        isLoading = true

        do {
            let authorization = try await oauthClient.requestDeviceAuthorization(
                clientID: config.githubOAuthClientID,
                scopes: ["repo", "read:org"]
            )

            sessionState = .awaitingAuthorization(authorization)
            isLoading = false

            authorizationTask = Task { [weak self] in
                guard let self else {
                    return
                }

                do {
                    let token = try await self.oauthClient.waitForAccessToken(
                        clientID: self.config.githubOAuthClientID,
                        authorization: authorization
                    )
                    await self.completeSignIn(with: token)
                } catch is CancellationError {
                    return
                } catch {
                    await self.failSignIn(error: error)
                }
            }
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    func cancelAuthorization() {
        authorizationTask?.cancel()
        authorizationTask = nil
        sessionState = .signedOut
    }

    func signOut() {
        authorizationTask?.cancel()
        authorizationTask = nil
        accessToken = nil
        currentUser = nil
        selectedFeedMode = .pullRequests
        pullRequests = []
        issues = []
        selectedRepositoryFilter = nil
        sessionState = .signedOut
        errorMessage = nil

        do {
            try tokenStore.deleteToken()
        } catch {
            errorMessage = "Failed to remove login token."
        }
    }

    func refresh() async {
        guard let token = accessToken, !token.isEmpty else {
            if case .awaitingAuthorization = sessionState {
                return
            }
            sessionState = .signedOut
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            async let pullRequestsPayload = apiClient.fetchOpenPullRequests(token: token)
            async let issuesPayload = apiClient.fetchOpenIssues(token: token)

            let (pullRequestsResult, issuesResult) = try await (pullRequestsPayload, issuesPayload)

            currentUser = pullRequestsResult.login
            pullRequests = pullRequestsResult.pullRequests
            issues = issuesResult.issues

            if let selectedRepositoryFilter, !activeFeedHasRepository(selectedRepositoryFilter) {
                self.selectedRepositoryFilter = nil
            }
            lastRefreshedAt = Date()
            sessionState = .signedIn
            isLoading = false
        } catch GitHubAPIError.unauthorized {
            isLoading = false
            errorMessage = "Session expired. Please sign in again."
            signOut()
        } catch {
            isLoading = false
            errorMessage = error.localizedDescription
        }
    }

    func openVerificationPage() {
        guard case let .awaitingAuthorization(authorization) = sessionState,
              let url = authorization.verificationURL
        else {
            return
        }

        NSWorkspace.shared.open(url)
    }

    func openPullRequest(_ pullRequest: PullRequest) {
        NSWorkspace.shared.open(pullRequest.url)
    }

    func openIssue(_ issue: Issue) {
        NSWorkspace.shared.open(issue.url)
    }

    func selectFeedMode(_ mode: FeedMode) {
        selectedFeedMode = mode
        if let selectedRepositoryFilter, !activeFeedHasRepository(selectedRepositoryFilter) {
            self.selectedRepositoryFilter = nil
        }
    }

    func selectRepositoryFilter(_ repositoryNameWithOwner: String?) {
        if let repositoryNameWithOwner, !repositoryNameWithOwner.isEmpty {
            selectedRepositoryFilter = repositoryNameWithOwner
        } else {
            selectedRepositoryFilter = nil
        }
    }

    func refreshOnMenuOpenIfNeeded() async {
        guard case .signedIn = sessionState else {
            return
        }

        guard !isLoading else {
            return
        }

        if let lastRefreshedAt,
           Date().timeIntervalSince(lastRefreshedAt) < menuOpenRefreshMinimumInterval {
            return
        }

        await refresh()
    }

    private func completeSignIn(with token: String) async {
        do {
            try tokenStore.saveToken(token)
            accessToken = token
            sessionState = .signedIn
            await refresh()
        } catch {
            sessionState = .signedOut
            errorMessage = "Failed to save login token."
        }
    }

    private func failSignIn(error: Error) async {
        sessionState = .signedOut
        isLoading = false
        errorMessage = error.localizedDescription
    }

    private var activeFeedRepositoryItems: [(repositoryNameWithOwner: String, updatedAt: Date)] {
        switch selectedFeedMode {
        case .pullRequests:
            return pullRequests.map { ($0.repositoryNameWithOwner, $0.updatedAt) }
        case .issues:
            return issues.map { ($0.repositoryNameWithOwner, $0.updatedAt) }
        }
    }

    private func activeFeedHasRepository(_ repositoryNameWithOwner: String) -> Bool {
        switch selectedFeedMode {
        case .pullRequests:
            return pullRequests.contains { $0.repositoryNameWithOwner == repositoryNameWithOwner }
        case .issues:
            return issues.contains { $0.repositoryNameWithOwner == repositoryNameWithOwner }
        }
    }
}
