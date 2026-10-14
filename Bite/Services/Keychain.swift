import Foundation
import LocalAuthentication
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

    /// Bytes, for your mirror's keys. When the item is behind Face ID, pass the context Face ID
    /// was just asked through so the Keychain doesn't ask again; without one it asks itself,
    /// holding the thread until it's answered.
    static func data(for account: String, context: LAContext? = nil) -> Data? {
        var query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        if let context { query[kSecUseAuthenticationContext as String] = context }
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Whether an item is there, asked so that nothing prompts: an item behind Face ID answers
    /// that it would need to ask, which means it exists. Only "not found" is missing.
    static func exists(_ account: String) -> Bool {
        let context = LAContext()
        context.interactionNotAllowed = true
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnAttributes as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
            kSecUseAuthenticationContext as String: context,
        ]
        var result: AnyObject?
        return SecItemCopyMatching(query as CFDictionary, &result) != errSecItemNotFound
    }

    /// Saves bytes on this phone only, never in a backup, or removes them when nil. `protected`
    /// puts them behind Face ID or the passcode (the protection then rides in the access
    /// control: an item can't carry both it and a plain accessibility). True when it worked.
    @discardableResult
    static func setData(_ data: Data?, for account: String, protected: Bool) -> Bool {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        let removed = SecItemDelete(identity as CFDictionary)
        guard let data else { return removed == errSecSuccess || removed == errSecItemNotFound }
        var item = identity
        item[kSecValueData as String] = data
        if protected {
            // Never biometry only: re-enrolling a face would lose the key and every photo, and
            // a few failed tries would lock you out with no way back but the passcode.
            guard let access = SecAccessControlCreateWithFlags(nil, kSecAttrAccessibleWhenUnlockedThisDeviceOnly, .userPresence, nil) else { return false }
            item[kSecAttrAccessControl as String] = access
        } else {
            item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlockedThisDeviceOnly
        }
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    /// Bytes kept in iCloud Keychain, end-to-end encrypted by Apple, on every iPhone signed in
    /// to the same Apple Account: your mirror's keys, when you keep your photos forever.
    static func syncedData(for account: String) -> Data? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: true,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        guard SecItemCopyMatching(query as CFDictionary, &result) == errSecSuccess else { return nil }
        return result as? Data
    }

    /// Saves bytes to iCloud Keychain, or removes them everywhere when nil. True when it worked.
    @discardableResult
    static func setSyncedData(_ data: Data?, for account: String) -> Bool {
        let identity: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecAttrSynchronizable as String: true,
        ]
        let removed = SecItemDelete(identity as CFDictionary)
        guard let data else { return removed == errSecSuccess || removed == errSecItemNotFound }
        var item = identity
        item[kSecValueData as String] = data
        item[kSecAttrAccessible as String] = kSecAttrAccessibleWhenUnlocked
        return SecItemAdd(item as CFDictionary, nil) == errSecSuccess
    }

    static let claudeKey = "claude-api-key"
    /// How every Anthropic API key starts, to tell a whole key from a stray fragment.
    static let claudeKeyPrefix = "sk-ant-"
}
