import Foundation
import Security

struct RuntimeRefreshCredential: Codable, Equatable, Sendable {
    let baseURL: String
    let refreshToken: String
    let refreshExpiresAt: Date
    let clientName: String
}

protocol RuntimeCredentialStore: Sendable {
    func load() throws -> RuntimeRefreshCredential?
    func save(_ credential: RuntimeRefreshCredential) throws
    func remove() throws
}

struct KeychainCredentialStore: RuntimeCredentialStore {
    private let service = "org.codexremote.app.runtime-auth"
    private let account = "refresh-session"

    func load() throws -> RuntimeRefreshCredential? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne
        ]
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        if status == errSecItemNotFound { return nil }
        guard status == errSecSuccess, let data = result as? Data else {
            throw KeychainError(status: status)
        }
        return try JSONDecoder().decode(RuntimeRefreshCredential.self, from: data)
    }

    func save(_ credential: RuntimeRefreshCredential) throws {
        let data = try JSONEncoder().encode(credential)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        ]
        let status = SecItemUpdate(query as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            var item = query
            attributes.forEach { item[$0.key] = $0.value }
            let addStatus = SecItemAdd(item as CFDictionary, nil)
            guard addStatus == errSecSuccess else { throw KeychainError(status: addStatus) }
        } else if status != errSecSuccess {
            throw KeychainError(status: status)
        }
    }

    func remove() throws {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account
        ]
        let status = SecItemDelete(query as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError(status: status)
        }
    }
}

struct KeychainError: LocalizedError {
    let status: OSStatus
    var errorDescription: String? { "Keychain error \(status)" }
}

final class MemoryCredentialStore: RuntimeCredentialStore, @unchecked Sendable {
    private let lock = NSLock()
    private var value: RuntimeRefreshCredential?

    init(value: RuntimeRefreshCredential? = nil) { self.value = value }

    func load() -> RuntimeRefreshCredential? { lock.withLock { value } }
    func save(_ credential: RuntimeRefreshCredential) { lock.withLock { value = credential } }
    func remove() { lock.withLock { value = nil } }
}
