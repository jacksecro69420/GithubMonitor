import Foundation

enum GitHubAPIError: LocalizedError {
    case invalidResponse
    case unauthorized
    case serverError(String)
    case decodingError

    var errorDescription: String? {
        switch self {
        case .invalidResponse:
            return "GitHub returned an invalid response."
        case .unauthorized:
            return "GitHub token is invalid or expired."
        case let .serverError(message):
            return message
        case .decodingError:
            return "Could not decode GitHub response."
        }
    }
}

struct OpenPullRequestsPayload {
    let login: String
    let pullRequests: [PullRequest]
}

struct GitHubAPIClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func fetchOpenPullRequests(token: String, repositoriesFirst: Int = 40, pullRequestsFirst: Int = 20) async throws -> OpenPullRequestsPayload {
        let query = """
        query OpenPullRequests($repositoriesFirst: Int!, $pullRequestsFirst: Int!) {
          viewer {
            login
            repositories(
              first: $repositoriesFirst,
              affiliations: [OWNER, COLLABORATOR, ORGANIZATION_MEMBER],
              isFork: false,
              orderBy: {field: UPDATED_AT, direction: DESC}
            ) {
              nodes {
                nameWithOwner
                pullRequests(first: $pullRequestsFirst, states: OPEN, orderBy: {field: UPDATED_AT, direction: DESC}) {
                  nodes {
                    id
                    number
                    title
                    url
                    updatedAt
                    isDraft
                    reviewDecision
                    author {
                      login
                    }
                  }
                }
              }
            }
          }
        }
        """

        let payload = GraphQLRequest(
            query: query,
            variables: [
                "repositoriesFirst": .number(repositoriesFirst),
                "pullRequestsFirst": .number(pullRequestsFirst)
            ]
        )

        var request = URLRequest(url: URL(string: "https://api.github.com/graphql")!)
        request.httpMethod = "POST"
        request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("2022-11-28", forHTTPHeaderField: "X-GitHub-Api-Version")
        request.httpBody = try JSONEncoder().encode(payload)

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubAPIError.invalidResponse
        }

        if http.statusCode == 401 {
            throw GitHubAPIError.unauthorized
        }

        guard (200 ... 299).contains(http.statusCode) else {
            throw GitHubAPIError.serverError("GitHub API error (\(http.statusCode)).")
        }

        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601

        do {
            let graphQLResponse = try decoder.decode(OpenPullRequestsGraphQLResponse.self, from: data)

            if let firstError = graphQLResponse.errors?.first {
                throw GitHubAPIError.serverError(firstError.message)
            }

            guard let viewer = graphQLResponse.data?.viewer else {
                throw GitHubAPIError.invalidResponse
            }

            var prsByID: [String: PullRequest] = [:]

            for repository in viewer.repositories.nodes {
                for node in repository.pullRequests.nodes {
                    prsByID[node.id] = PullRequest(
                        id: node.id,
                        number: node.number,
                        title: node.title,
                        url: node.url,
                        repositoryNameWithOwner: repository.nameWithOwner,
                        authorLogin: node.author?.login ?? "unknown",
                        updatedAt: node.updatedAt,
                        isDraft: node.isDraft,
                        reviewDecision: node.reviewDecision
                    )
                }
            }

            let prs = prsByID.values.sorted { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }

            return OpenPullRequestsPayload(login: viewer.login, pullRequests: prs)
        } catch let apiError as GitHubAPIError {
            throw apiError
        } catch {
            throw GitHubAPIError.decodingError
        }
    }
}

private struct GraphQLRequest: Encodable {
    let query: String
    let variables: [String: GraphQLValue]
}

private enum GraphQLValue: Encodable {
    case string(String)
    case number(Int)

    func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case let .string(value):
            try container.encode(value)
        case let .number(value):
            try container.encode(value)
        }
    }
}

private struct OpenPullRequestsGraphQLResponse: Decodable {
    let data: DataNode?
    let errors: [GraphQLErrorItem]?

    struct DataNode: Decodable {
        let viewer: Viewer
    }

    struct Viewer: Decodable {
        let login: String
        let repositories: RepositoryConnection
    }

    struct RepositoryConnection: Decodable {
        let nodes: [RepositoryNode]
    }

    struct RepositoryNode: Decodable {
        let nameWithOwner: String
        let pullRequests: PullRequestConnection
    }

    struct PullRequestConnection: Decodable {
        let nodes: [PullRequestNode]
    }

    struct PullRequestNode: Decodable {
        let id: String
        let number: Int
        let title: String
        let url: URL
        let updatedAt: Date
        let isDraft: Bool
        let reviewDecision: PullRequestReviewDecision?
        let author: Author?
    }

    struct Author: Decodable {
        let login: String
    }

    struct GraphQLErrorItem: Decodable {
        let message: String
    }
}
