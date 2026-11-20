import Foundation
import Security

/// Integration secrets (the Slack token, the webhook secret) in the Mac's Keychain, never in
/// UserDefaults, Firestore, the functions or git. One generic-password item per name.
enum Keychain {
    static let service = "com.zenmodeos.zenmode.integrations"

    static func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var item: CFTypeRef?
        guard SecItemCopyMatching(query as CFDictionary, &item) == errSecSuccess, let data = item as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    @discardableResult
    static func write(_ value: String?, for account: String) -> Bool {
        let base: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(base as CFDictionary)
        guard let value, !value.isEmpty else { return true }
        var add = base
        add[kSecValueData as String] = Data(value.utf8)
        add[kSecAttrAccessible as String] = kSecAttrAccessibleAfterFirstUnlock
        return SecItemAdd(add as CFDictionary, nil) == errSecSuccess
    }
}

/// The secrets Focus Mode's hooks read, cached in memory so a hook never blocks on the Keychain.
final class FocusSecrets: @unchecked Sendable {
    static let shared = FocusSecrets()
    private let lock = NSLock()
    private var cache: [String: String?] = [:]

    static let slackToken = "slack.user-token"
    static let webhookSecret = "webhook.secret"

    func value(_ account: String) -> String? {
        lock.lock()
        defer { lock.unlock() }
        if let hit = cache[account] { return hit }
        let v = Keychain.read(account)
        cache[account] = v
        return v
    }

    func set(_ value: String?, _ account: String) {
        Keychain.write(value, for: account)
        lock.lock()
        cache[account] = value
        lock.unlock()
    }
}
