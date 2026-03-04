import Foundation

enum PullRequestReviewDecision: String, Decodable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case reviewRequired = "REVIEW_REQUIRED"
}

enum PullRequestStatus: String {
    case draft = "Draft"
    case approved = "Approved"
    case changesRequested = "Changes Requested"
    case reviewRequired = "Review Required"
}

struct PullRequest: Identifiable, Hashable {
    let id: String
    let number: Int
    let title: String
    let url: URL
    let repositoryNameWithOwner: String
    let authorLogin: String
    let updatedAt: Date
    let isDraft: Bool
    let reviewDecision: PullRequestReviewDecision?

    var status: PullRequestStatus {
        if isDraft {
            return .draft
        }

        switch reviewDecision {
        case .approved:
            return .approved
        case .changesRequested:
            return .changesRequested
        case .reviewRequired, .none:
            return .reviewRequired
        }
    }
}
