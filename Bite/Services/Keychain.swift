import Foundation
import Security

/// Keeps secrets, like your Claude API key, in the iOS Keychain instead of app storage.
enum Keychain {
    /// Bite Demo keeps its own, so it never reads or removes Bite's.
    private static var service: String { BiteStore.isDemo ? "com.dylan.bite.demo" : "com.dylan.bite" }

    static func string(for account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess,
              let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Saves the value, or removes it when nil or empty. A new value replaces the old one in
    /// place, so a save that fails leaves the old value where it was. True when it worked.
    @discardableResult
    static func set(_ value: String?, for account: String) -> Bool {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else {
            let status = SecItemDelete(identity as CFDictionary)
            return status == errSecSuccess || status == errSecItemNotFound
        }
        let attributes: [String: Any] = [
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        let status = SecItemUpdate(identity as CFDictionary, attributes as CFDictionary)
        guard status == errSecItemNotFound else { return status == errSecSuccess }
        let item = identity.merging(attributes) { _, new in new }
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static let claudeKey = "claude-api-key"
    /// How every Anthropic API key starts, to tell a whole key from a stray fragment.
    static let claudeKeyPrefix = "sk-ant-"
}
