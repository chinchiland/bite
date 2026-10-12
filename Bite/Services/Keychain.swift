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

    /// Saves the value, or removes it when nil or empty.
    static func set(_ value: String?, for account: String) {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(identity as CFDictionary)
        guard let value, !value.isEmpty, let data = value.data(using: .utf8) else { return }
        var item = identity
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly
        SecItemAdd(item as CFDictionary, nil)
    }

    static let claudeKey = "claude-api-key"
    /// How every Anthropic API key starts, to tell a whole key from a stray fragment.
    static let claudeKeyPrefix = "sk-ant-"
}
