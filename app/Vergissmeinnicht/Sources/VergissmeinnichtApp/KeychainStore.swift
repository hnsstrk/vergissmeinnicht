import Foundation
import Security

/// Liest und schreibt Sync-Credentials im macOS-Keychain.
///
/// Service: `de.hnsstrk.vergissmeinnicht.sync`
/// Accessibility: `kSecAttrAccessibleWhenUnlockedThisDeviceOnly`
enum KeychainStore {
    private static let service = "de.hnsstrk.vergissmeinnicht.sync"

    enum Key: String {
        case serverUrl          = "serverUrl"
        case clientId           = "clientId"
        case encryptionSecret   = "encryptionSecret"
    }

    enum KeychainError: Error {
        case encodingFailed
        case unexpectedStatus(OSStatus)
    }

    static func save(_ value: String, for key: Key) throws {
        guard let data = value.data(using: .utf8) else {
            throw KeychainError.encodingFailed
        }
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key.rawValue,
        ]
        let updateAttrs: [CFString: Any] = [
            kSecValueData:      data,
            kSecAttrAccessible: kSecAttrAccessibleWhenUnlockedThisDeviceOnly,
        ]
        let status = SecItemUpdate(query as CFDictionary, updateAttrs as CFDictionary)
        if status == errSecItemNotFound {
            var addQuery = query
            addQuery[kSecValueData]      = data
            addQuery[kSecAttrAccessible] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
            let addStatus = SecItemAdd(addQuery as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unexpectedStatus(addStatus)
            }
        } else if status != errSecSuccess {
            throw KeychainError.unexpectedStatus(status)
        }
    }

    static func load(key: Key) -> String? {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key.rawValue,
            kSecReturnData:  true,
            kSecMatchLimit:  kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess,
              let data = result as? Data,
              let value = String(data: data, encoding: .utf8)
        else { return nil }
        return value
    }

    static func delete(key: Key) throws {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrService: service,
            kSecAttrAccount: key.rawValue,
        ]
        let status = SecItemDelete(query as CFDictionary)
        // errSecItemNotFound ist kein Fehler — idempotentes Delete.
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unexpectedStatus(status)
        }
    }
}
