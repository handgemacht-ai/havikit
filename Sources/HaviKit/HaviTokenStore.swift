import Foundation
import Security

/// HaviKit's own Keychain-backed credential store under a **distinct** service
/// string `ai.handgemacht.havikit`, kept separate from the app's
/// `KeychainTokenStorage` (`ai.handgemacht.lesewerkstatt`) so the dogfood
/// identity never mixes with the child's account and the two lifecycles are
/// independent (design §1). The stamped `devToken` is a fallback source only and
/// is never written here. Manual-paste and device-code credentials, when
/// present, override the stamped token.
public final class HaviTokenStore: @unchecked Sendable {
    private let service = "ai.handgemacht.havikit"

    private enum Key {
        static let accessToken = "havi.access_token"
        static let workspaceID = "havi.workspace_id"
        static let refreshToken = "havi.refresh_token"
        static let expiresAt = "havi.expires_at"
    }

    public init() {}

    public var accessToken: String? { get(Key.accessToken) }
    public var workspaceID: String? { get(Key.workspaceID) }
    public var refreshToken: String? { get(Key.refreshToken) }

    public var expiresAt: Date? {
        guard let raw = get(Key.expiresAt), let seconds = TimeInterval(raw) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    public var hasCredential: Bool {
        accessToken != nil && workspaceID != nil
    }

    /// Manual-paste dev fallback (design §5): a bearer token + workspace id
    /// copied from the dashboard, overriding the stamped values.
    public func signIn(token: String, workspaceID: String) {
        set(token, forKey: Key.accessToken)
        set(workspaceID, forKey: Key.workspaceID)
    }

    /// Device-code result (design §5, v1.1): full session with optional refresh.
    public func storeSession(accessToken: String, workspaceID: String, refreshToken: String?, expiresAt: Date?) {
        set(accessToken, forKey: Key.accessToken)
        set(workspaceID, forKey: Key.workspaceID)
        if let refreshToken {
            set(refreshToken, forKey: Key.refreshToken)
        } else {
            delete(Key.refreshToken)
        }
        if let expiresAt {
            set(String(expiresAt.timeIntervalSince1970), forKey: Key.expiresAt)
        } else {
            delete(Key.expiresAt)
        }
    }

    public func clear() {
        delete(Key.accessToken)
        delete(Key.workspaceID)
        delete(Key.refreshToken)
        delete(Key.expiresAt)
    }

    // MARK: - Keychain helpers

    private func set(_ value: String, forKey key: String) {
        guard let data = value.data(using: .utf8) else { return }
        delete(key)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecValueData as String: data,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    private func get(_ key: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    private func delete(_ key: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: key,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
