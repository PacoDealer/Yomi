import Foundation
import Security

// MARK: - KeychainHelper

enum KeychainHelper {

    /// Save or update a string value in the keychain.
    static func save(_ value: String, for key: String) {
        let data = Data(value.utf8)
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: Bundle.main.bundleIdentifier ?? "com.yomi.app"
        ]
        // Try update first
        let updateAttributes: [CFString: Any] = [kSecValueData: data]
        let status = SecItemUpdate(query as CFDictionary, updateAttributes as CFDictionary)
        if status == errSecItemNotFound {
            // Item doesn't exist — insert it
            var addQuery = query
            addQuery[kSecValueData] = data
            SecItemAdd(addQuery as CFDictionary, nil)
        }
    }

    /// Load a string value from the keychain. Returns nil if not found.
    static func load(for key: String) -> String? {
        let query: [CFString: Any] = [
            kSecClass:            kSecClassGenericPassword,
            kSecAttrAccount:      key,
            kSecAttrService:      Bundle.main.bundleIdentifier ?? "com.yomi.app",
            kSecReturnData:       true,
            kSecMatchLimit:       kSecMatchLimitOne
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Delete a value from the keychain.
    static func delete(for key: String) {
        let query: [CFString: Any] = [
            kSecClass:       kSecClassGenericPassword,
            kSecAttrAccount: key,
            kSecAttrService: Bundle.main.bundleIdentifier ?? "com.yomi.app"
        ]
        SecItemDelete(query as CFDictionary)
    }
}
