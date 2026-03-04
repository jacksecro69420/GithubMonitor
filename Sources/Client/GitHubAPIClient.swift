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

    func fetchOpenPullRequests(token: String, first: Int = 30) async throws -> OpenPullRequestsPayload {
        let query = """
        query OpenPullRequests($first: Int!) {
          viewer {
            login
            pullRequests(first: $first, states: OPEN, orderBy: {field: UPDATED_AT, direction: DESC}) {
              nodes {
                id
                number
                title
                url
                updatedAt
                repository {
                  nameWithOwner
                }
              }
            }
          }
        }
        """

        let payload = GraphQLRequest(
            query: query,
            variables: ["first": .number(first)]
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

            let prs = viewer.pullRequests.nodes.map {
                PullRequest(
                    id: $0.id,
                    number: $0.number,
                    title: $0.title,
                    url: $0.url,
                    repositoryNameWithOwner: $0.repository.nameWithOwner,
                    updatedAt: $0.updatedAt
                )
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
        let repository: Repository
    }

    struct Repository: Decodable {
        let nameWithOwner: String
    }

    struct GraphQLErrorItem: Decodable {
        let message: String
    }
}
