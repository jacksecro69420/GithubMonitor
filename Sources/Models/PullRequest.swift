import Foundation

struct PullRequest: Identifiable, Hashable {
    let id: String
    let number: Int
    let title: String
    let url: URL
    let repositoryNameWithOwner: String
    let updatedAt: Date
}
