import Foundation

struct AppConfig {
    let githubOAuthClientID: String

    init(bundle: Bundle = .main, environment: [String: String] = ProcessInfo.processInfo.environment) {
        let envClientID = environment["GITHUB_CLIENT_ID"]?.trimmingCharacters(in: .whitespacesAndNewlines)
        if let envClientID, !envClientID.isEmpty {
            githubOAuthClientID = envClientID
            return
        }

        let plistClientID = (bundle.object(forInfoDictionaryKey: "GitHubOAuthClientID") as? String)?
            .trimmingCharacters(in: .whitespacesAndNewlines)

        if let plistClientID, !plistClientID.isEmpty, plistClientID != "__GITHUB_CLIENT_ID__" {
            githubOAuthClientID = plistClientID
        } else {
            githubOAuthClientID = ""
        }
    }

    var hasClientID: Bool {
        !githubOAuthClientID.isEmpty
    }
}
