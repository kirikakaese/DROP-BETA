import DROPCore
import Foundation
import Security
import os

/// Stores secrets by account name. The live store is the Keychain; nothing secret is ever written
/// to files, `UserDefaults` or the metadata database.
public protocol SecretStoring: Sendable {
    func data(for account: String) throws -> Data?
    func setData(_ data: Data, for account: String) throws
    func deleteData(for account: String) throws
}

/// `SecretStoring` in the login keychain: generic passwords, this device only, never synchronized.
public struct KeychainSecretStore: SecretStoring {
    let service: String

    public init(service: String) {
        self.service = service
    }

    public func data(for account: String) throws -> Data? {
        var query = baseQuery(account)
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw Self.error(status)
        }
    }

    public func setData(_ data: Data, for account: String) throws {
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        var status = SecItemUpdate(baseQuery(account) as CFDictionary, attributes as CFDictionary)
        if status == errSecItemNotFound {
            let query = baseQuery(account).merging(attributes) { _, new in new }
            status = SecItemAdd(query as CFDictionary, nil)
        }
        guard status == errSecSuccess else { throw Self.error(status) }
    }

    public func deleteData(for account: String) throws {
        let status = SecItemDelete(baseQuery(account) as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else { throw Self.error(status) }
    }

    private func baseQuery(_ account: String) -> [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: false,
        ]
    }

    private static func error(_ status: OSStatus) -> DROPError {
        let message = SecCopyErrorMessageString(status, nil) as String? ?? "OSStatus \(status)"
        Log.keychain.error("Keychain error \(status, privacy: .public)")
        return DROPError(
            .keychain,
            whatHappened: String(localized: "DROP could not use the Keychain."),
            howToFix: String(localized: "Make sure your login keychain is unlocked, then try again."),
            details: message
        )
    }
}

/// `SecretStoring` in memory, for tests and previews.
public final class InMemorySecretStore: SecretStoring, Sendable {
    private let items: OSAllocatedUnfairLock<[String: Data]>

    public init(items: [String: Data] = [:]) {
        self.items = OSAllocatedUnfairLock(initialState: items)
    }

    public func data(for account: String) throws -> Data? {
        items.withLock { $0[account] }
    }

    public func setData(_ data: Data, for account: String) throws {
        items.withLock { $0[account] = data }
    }

    public func deleteData(for account: String) throws {
        _ = items.withLock { $0.removeValue(forKey: account) }
    }
}
