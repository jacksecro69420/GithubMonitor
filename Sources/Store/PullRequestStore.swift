import AppKit
import Foundation
import Observation

enum SessionState {
    case missingClientID
    case signedOut
    case awaitingAuthorization(DeviceAuthorization)
    case signedIn
}

@MainActor
@Observable
final class PullRequestStore {
    private let config: AppConfig
    private let oauthClient: GitHubOAuthDeviceClient
    private let apiClient: GitHubAPIClient
    private let tokenStore: TokenStore

    private var accessToken: String?
    private var hasRestoredSession = false
    private var authorizationTask: Task<Void, Never>?

    private(set) var sessionState: SessionState = .signedOut
    private(set) var currentUser: String?
    private(set) var pullRequests: [PullRequest] = []
    private(set) var isLoading = false
    private(set) var errorMessage: String?
    private(set) var lastRefreshedAt: Date?

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
        pullRequests = []
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
            let payload = try await apiClient.fetchOpenPullRequests(token: token)
            currentUser = payload.login
            pullRequests = payload.pullRequests
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
}
