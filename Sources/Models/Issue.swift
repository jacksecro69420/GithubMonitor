import Foundation

struct IssueLabel: Identifiable, Hashable {
    let id: String
    let name: String
    let colorHex: String
}

struct Issue: Identifiable, Hashable {
    let id: String
    let number: Int
    let title: String
    let url: URL
    let repositoryNameWithOwner: String
    let authorLogin: String
    let updatedAt: Date
    let labels: [IssueLabel]

    var statusText: String {
        "Open"
    }
}
