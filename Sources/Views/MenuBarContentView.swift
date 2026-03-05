import SwiftUI

struct MenuBarContentView: View {
    let store: PullRequestStore

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header
            if case .signedIn = store.sessionState {
                signedInToolbar
            }

            if let errorMessage = store.errorMessage {
                Text(errorMessage)
                    .font(.footnote)
                    .foregroundStyle(.red)
            }

            content

            Spacer(minLength: 0)
        }
        .padding(14)
        .onAppear {
            Task {
                await store.refreshOnMenuOpenIfNeeded()
            }
        }
    }

    @ViewBuilder
    private var content: some View {
        switch store.sessionState {
        case .missingClientID:
            missingClientIDView
        case .signedOut:
            signedOutView
        case let .awaitingAuthorization(authorization):
            authorizationView(authorization)
        case .signedIn:
            signedInView
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            Text(store.selectedFeedHeading)
                .font(.headline)

            Spacer()

            if let currentUser = store.currentUser, case .signedIn = store.sessionState {
                Text("@\(currentUser)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    private var signedOutView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Sign in to list your recently updated open pull requests and open issues.")
                .font(.subheadline)
                .foregroundStyle(.secondary)

            Button {
                Task {
                    await store.beginDeviceLogin()
                }
            } label: {
                if store.isLoading {
                    ProgressView()
                        .controlSize(.small)
                } else {
                    Text("Sign in with GitHub")
                }
            }
        }
    }

    private func authorizationView(_ authorization: DeviceAuthorization) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("1) Open GitHub verification page")
            Text("2) Enter this code:")
                .foregroundStyle(.secondary)
                .font(.subheadline)

            Text(authorization.userCode)
                .font(.system(.title3, design: .monospaced).bold())
                .textSelection(.enabled)

            HStack {
                Button("Open Verification Page") {
                    store.openVerificationPage()
                }

                Button("Cancel") {
                    store.cancelAuthorization()
                }
            }

            Text("Waiting for GitHub authorization...")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private var signedInView: some View {
        VStack(alignment: .leading, spacing: 8) {
            feedToggle

            if store.isLoading, store.isSelectedFeedEmpty {
                loadingPlaceholderCards
            } else if store.isSelectedFeedEmpty {
                Text("No open \(store.selectedFeedMode == .pullRequests ? "pull requests" : "issues") found.")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            } else {
                repoFiltersBar

                HStack {
                    Text("\(store.filteredItemCount) result\(store.filteredItemCount == 1 ? "" : "s")")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Spacer()

                    if let selectedRepository = store.selectedRepositoryFilter {
                        Text(selectedRepository)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }

                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        switch store.selectedFeedMode {
                        case .pullRequests:
                            ForEach(store.filteredPullRequests) { pullRequest in
                                PullRequestRowView(pullRequest: pullRequest) {
                                    store.openPullRequest(pullRequest)
                                }
                            }
                        case .issues:
                            ForEach(store.filteredIssues) { issue in
                                IssueRowView(issue: issue) {
                                    store.openIssue(issue)
                                }
                            }
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
        }
    }

    private var loadingPlaceholderCards: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(0 ..< 6, id: \.self) { _ in
                    placeholderCard
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var placeholderCard: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .top, spacing: 8) {
                Text(placeholderTitleText)
                    .font(.system(size: 13, weight: .semibold))
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)

                Spacer(minLength: 6)

                PillView(
                    text: placeholderStatusText,
                    color: placeholderStatusColor
                )
            }

            HStack(spacing: 6) {
                Text("owner/repository")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("•")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.7))

                Text("5m ago")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)

                Text("•")
                    .font(.system(size: 9, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.7))

                Text("@contributor")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(.secondary)
            }

            if store.selectedFeedMode == .issues {
                HStack(spacing: 4) {
                    PillView(text: "bug", color: .red)
                    PillView(text: "triage", color: .purple)
                }
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.secondary.opacity(0.1))
        )
        .redacted(reason: .placeholder)
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    private var feedToggle: some View {
        Picker("Feed", selection: feedSelectionBinding) {
            ForEach(FeedMode.allCases) { mode in
                Text(mode.title).tag(mode)
            }
        }
        .pickerStyle(.segmented)
    }

    private var repoFiltersBar: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                Button {
                    store.selectRepositoryFilter(nil)
                } label: {
                    PillView(
                        text: "All \(allCountForActiveFeed)",
                        color: .secondary,
                        isSelected: store.selectedRepositoryFilter == nil
                    )
                }
                .buttonStyle(.plain)

                ForEach(store.recentRepositoryFilters, id: \.self) { repository in
                    Button {
                        store.selectRepositoryFilter(repository)
                    } label: {
                        PillView(
                            text: "\(shortRepositoryName(repository)) \(count(for: repository))",
                            color: color(for: repository),
                            isSelected: store.selectedRepositoryFilter == repository
                        )
                    }
                    .buttonStyle(.plain)
                    .help(repository)
                }
            }
            .padding(.vertical, 1)
        }
    }

    private var signedInToolbar: some View {
        HStack(spacing: 8) {
            Button {
                Task {
                    await store.refresh()
                }
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(.secondary)
                    .padding(6)
                    .background(
                        RoundedRectangle(cornerRadius: 7, style: .continuous)
                            .fill(Color.secondary.opacity(0.12))
                    )
            }
            .buttonStyle(.plain)
            .help("Refresh")

            if store.isLoading {
                ProgressView()
                    .controlSize(.small)
            }

            if let lastRefreshedAt = store.lastRefreshedAt {
                Text("Updated \(lastRefreshedAt.formatted(date: .omitted, time: .shortened))")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button {
                store.signOut()
            } label: {
                Image(systemName: "rectangle.portrait.and.arrow.right")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(.secondary.opacity(0.75))
                    .padding(.horizontal, 4)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.plain)
            .help("Sign out")
        }
    }

    private var missingClientIDView: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("GitHub OAuth client ID is not configured.")
                .font(.subheadline)

            Text("Set GitHubOAuthClientID in Project.swift (Info.plist) or export GITHUB_CLIENT_ID before launching.")
                .font(.footnote)
                .foregroundStyle(.secondary)
        }
    }

    private func shortRepositoryName(_ repository: String) -> String {
        if let last = repository.split(separator: "/").last {
            return String(last)
        }
        return repository
    }

    private func count(for repository: String) -> Int {
        switch store.selectedFeedMode {
        case .pullRequests:
            return store.pullRequests.filter { $0.repositoryNameWithOwner == repository }.count
        case .issues:
            return store.issues.filter { $0.repositoryNameWithOwner == repository }.count
        }
    }

    private func color(for repository: String) -> Color {
        let palette: [Color] = [.blue, .mint, .orange, .teal, .indigo, .green]
        let hash = repository.unicodeScalars.reduce(0) { partial, scalar in
            ((partial * 31) + Int(scalar.value)) & 0x7fff_ffff
        }
        return palette[hash % palette.count]
    }

    private var allCountForActiveFeed: Int {
        switch store.selectedFeedMode {
        case .pullRequests:
            return store.pullRequests.count
        case .issues:
            return store.issues.count
        }
    }

    private var feedSelectionBinding: Binding<FeedMode> {
        Binding(
            get: { store.selectedFeedMode },
            set: { store.selectFeedMode($0) }
        )
    }

    private var placeholderTitleText: String {
        switch store.selectedFeedMode {
        case .pullRequests:
            return "#12345 Placeholder pull request title"
        case .issues:
            return "#12345 Placeholder issue title"
        }
    }

    private var placeholderStatusText: String {
        switch store.selectedFeedMode {
        case .pullRequests:
            return "Review Required"
        case .issues:
            return "Open"
        }
    }

    private var placeholderStatusColor: Color {
        switch store.selectedFeedMode {
        case .pullRequests:
            return .blue
        case .issues:
            return .mint
        }
    }
}
