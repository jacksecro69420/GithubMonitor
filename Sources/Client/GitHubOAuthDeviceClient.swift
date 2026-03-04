import Foundation

enum GitHubOAuthError: LocalizedError {
    case invalidClientID
    case invalidResponse
    case serverError(String)
    case authorizationTimedOut

    var errorDescription: String? {
        switch self {
        case .invalidClientID:
            return "Missing GitHub OAuth client ID."
        case .invalidResponse:
            return "GitHub returned an invalid response."
        case let .serverError(message):
            return message
        case .authorizationTimedOut:
            return "Authorization timed out. Please try again."
        }
    }
}

struct DeviceAuthorization: Decodable {
    let deviceCode: String
    let userCode: String
    let verificationURI: String
    let expiresIn: Int
    let interval: Int

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case expiresIn = "expires_in"
        case interval
    }

    var verificationURL: URL? {
        URL(string: verificationURI)
    }
}

private struct AccessTokenResponse: Decodable {
    let accessToken: String?
    let tokenType: String?
    let scope: String?
    let error: String?
    let errorDescription: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case tokenType = "token_type"
        case scope
        case error
        case errorDescription = "error_description"
    }
}

struct GitHubOAuthDeviceClient {
    private let session: URLSession

    init(session: URLSession = .shared) {
        self.session = session
    }

    func requestDeviceAuthorization(clientID: String, scopes: [String]) async throws -> DeviceAuthorization {
        guard !clientID.isEmpty else {
            throw GitHubOAuthError.invalidClientID
        }

        let url = URL(string: "https://github.com/login/device/code")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "scope", value: scopes.joined(separator: " "))
        ]
        request.httpBody = body.percentEncoded()

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubOAuthError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw GitHubOAuthError.serverError("Failed to start GitHub login (\(http.statusCode)).")
        }

        return try JSONDecoder().decode(DeviceAuthorization.self, from: data)
    }

    func waitForAccessToken(clientID: String, authorization: DeviceAuthorization) async throws -> String {
        guard !clientID.isEmpty else {
            throw GitHubOAuthError.invalidClientID
        }

        var intervalSeconds = max(authorization.interval, 1)
        let deadline = Date().addingTimeInterval(TimeInterval(authorization.expiresIn))

        while Date() < deadline {
            try await Task.sleep(for: .seconds(intervalSeconds))
            let response = try await exchangeDeviceCode(clientID: clientID, deviceCode: authorization.deviceCode)

            if let token = response.accessToken, !token.isEmpty {
                return token
            }

            if let error = response.error {
                switch error {
                case "authorization_pending":
                    continue
                case "slow_down":
                    intervalSeconds += 5
                case "expired_token":
                    throw GitHubOAuthError.authorizationTimedOut
                default:
                    let details = response.errorDescription ?? error
                    throw GitHubOAuthError.serverError("GitHub login failed: \(details)")
                }
            }
        }

        throw GitHubOAuthError.authorizationTimedOut
    }

    private func exchangeDeviceCode(clientID: String, deviceCode: String) async throws -> AccessTokenResponse {
        let url = URL(string: "https://github.com/login/oauth/access_token")!
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = [
            URLQueryItem(name: "client_id", value: clientID),
            URLQueryItem(name: "device_code", value: deviceCode),
            URLQueryItem(name: "grant_type", value: "urn:ietf:params:oauth:grant-type:device_code")
        ]
        request.httpBody = body.percentEncoded()

        let (data, response) = try await session.data(for: request)
        guard let http = response as? HTTPURLResponse else {
            throw GitHubOAuthError.invalidResponse
        }
        guard (200 ... 299).contains(http.statusCode) else {
            throw GitHubOAuthError.serverError("Failed to complete GitHub login (\(http.statusCode)).")
        }

        return try JSONDecoder().decode(AccessTokenResponse.self, from: data)
    }
}

private extension Array where Element == URLQueryItem {
    func percentEncoded() -> Data? {
        var components = URLComponents()
        components.queryItems = self
        return components.percentEncodedQuery?.data(using: .utf8)
    }
}
