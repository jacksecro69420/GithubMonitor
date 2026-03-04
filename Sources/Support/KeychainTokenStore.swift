import Foundation
import Security

enum KeychainTokenStoreError: Error {
    case readFailed(OSStatus)
    case saveFailed(OSStatus)
    case deleteFailed(OSStatus)
}

protocol TokenStore {
    func readToken() throws -> String?
    func saveToken(_ token: String) throws
    func deleteToken() throws
}

struct KeychainTokenStore: TokenStore {
    private let service = "com.dimillian.GithubMonitor"
    private let account = "github-access-token"

    func readToken() throws -> String? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne

        var item: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &item)

        if status == errSecItemNotFound {
            return nil
        }

        guard status == errSecSuccess else {
            throw KeychainTokenStoreError.readFailed(status)
        }

        guard
            let data = item as? Data,
            let token = String(data: data, encoding: .utf8)
        else {
            return nil
        }

        return token
    }

    func saveToken(_ token: String) throws {
        let data = Data(token.utf8)
        try deleteIfExists()

        var query = baseQuery
        query[kSecValueData as String] = data

        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else {
            throw KeychainTokenStoreError.saveFailed(status)
        }
    }

    func deleteToken() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainTokenStoreError.deleteFailed(status)
        }
    }

    private func deleteIfExists() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)

        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainTokenStoreError.deleteFailed(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
    }
}
