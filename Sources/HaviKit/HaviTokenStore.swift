import Foundation
#if canImport(Security)
import Security
#endif

/// Backing for `HaviTokenStore`'s string items. Production resolves the Keychain
/// backing; the poll-state-machine and persistence tests inject an in-memory
/// backing so nothing touches the real Keychain (design §1, §5).
protocol HaviCredentialBacking: Sendable {
    func read(_ account: String) -> String?
    func write(_ value: String, account: String)
    func delete(_ account: String)
}

/// The connected HAVI identity resolved by the device-code flow (design §5): the
/// bearer credential plus the display names the connect sheet shows in its
/// success + "Connected as …" states.
public struct HaviConnectedSession: Sendable, Equatable {
    public let accessToken: String
    public let workspaceID: String
    public let refreshToken: String?
    public let expiresAt: Date?
    public let userName: String?
    public let workspaceName: String?

    public init(
        accessToken: String,
        workspaceID: String,
        refreshToken: String? = nil,
        expiresAt: Date? = nil,
        userName: String? = nil,
        workspaceName: String? = nil
    ) {
        self.accessToken = accessToken
        self.workspaceID = workspaceID
        self.refreshToken = refreshToken
        self.expiresAt = expiresAt
        self.userName = userName
        self.workspaceName = workspaceName
    }
}

/// HaviKit's own credential store under a **distinct** service string
/// `ai.handgemacht.havikit`, kept separate from the app's `KeychainTokenStorage`
/// (`ai.handgemacht.lesewerkstatt`) so the dogfood identity never mixes with the
/// child's account and the two lifecycles are independent (design §1). The
/// stamped `devToken` is a fallback source only and is never written here.
/// Manual-paste and device-code credentials, when present, override the stamped
/// token.
public final class HaviTokenStore: @unchecked Sendable {
    private enum Key {
        static let accessToken = "havi.access_token"
        static let workspaceID = "havi.workspace_id"
        static let refreshToken = "havi.refresh_token"
        static let expiresAt = "havi.expires_at"
        static let userName = "havi.user_name"
        static let workspaceName = "havi.workspace_name"
    }

    private let backing: HaviCredentialBacking

    public init() {
        #if canImport(Security)
        self.backing = HaviKeychainBacking(service: "ai.handgemacht.havikit")
        #else
        self.backing = HaviInMemoryCredentialBacking()
        #endif
    }

    init(backing: HaviCredentialBacking) {
        self.backing = backing
    }

    public var accessToken: String? { backing.read(Key.accessToken) }
    public var workspaceID: String? { backing.read(Key.workspaceID) }
    public var refreshToken: String? { backing.read(Key.refreshToken) }
    public var userName: String? { backing.read(Key.userName) }
    public var workspaceName: String? { backing.read(Key.workspaceName) }

    public var expiresAt: Date? {
        guard let raw = backing.read(Key.expiresAt), let seconds = TimeInterval(raw) else { return nil }
        return Date(timeIntervalSince1970: seconds)
    }

    public var hasCredential: Bool {
        accessToken != nil && workspaceID != nil
    }

    /// The stored identity reassembled for the connect sheet's "Connected as …"
    /// row, or `nil` when no credential is present.
    public var connectedSession: HaviConnectedSession? {
        guard let accessToken, let workspaceID else { return nil }
        return HaviConnectedSession(
            accessToken: accessToken,
            workspaceID: workspaceID,
            refreshToken: refreshToken,
            expiresAt: expiresAt,
            userName: userName,
            workspaceName: workspaceName
        )
    }

    /// Manual-paste dev fallback (design §5): a bearer token + workspace id copied
    /// from the dashboard, overriding the stamped values.
    public func signIn(token: String, workspaceID: String) {
        backing.write(token, account: Key.accessToken)
        backing.write(workspaceID, account: Key.workspaceID)
        backing.delete(Key.refreshToken)
        backing.delete(Key.expiresAt)
        backing.delete(Key.userName)
        backing.delete(Key.workspaceName)
    }

    /// Device-code result (design §5): the full session, including the display
    /// names shown in the connect sheet.
    public func store(_ session: HaviConnectedSession) {
        backing.write(session.accessToken, account: Key.accessToken)
        backing.write(session.workspaceID, account: Key.workspaceID)
        writeOrDelete(session.refreshToken, account: Key.refreshToken)
        writeOrDelete(session.expiresAt.map { String($0.timeIntervalSince1970) }, account: Key.expiresAt)
        writeOrDelete(session.userName, account: Key.userName)
        writeOrDelete(session.workspaceName, account: Key.workspaceName)
    }

    public func clear() {
        backing.delete(Key.accessToken)
        backing.delete(Key.workspaceID)
        backing.delete(Key.refreshToken)
        backing.delete(Key.expiresAt)
        backing.delete(Key.userName)
        backing.delete(Key.workspaceName)
    }

    private func writeOrDelete(_ value: String?, account: String) {
        if let value {
            backing.write(value, account: account)
        } else {
            backing.delete(account)
        }
    }
}

#if canImport(Security)
/// Keychain-backed generic-password store used in production.
struct HaviKeychainBacking: HaviCredentialBacking {
    let service: String

    func read(_ account: String) -> String? {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecReturnData as String: true,
            kSecMatchLimit as String: kSecMatchLimitOne,
        ]
        var result: AnyObject?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        guard status == errSecSuccess, let data = result as? Data else { return nil }
        return String(data: data, encoding: .utf8)
    }

    /// Delete-then-add, so an item written before `kSecAttrAccessible` was set
    /// picks the attribute up on the next store. The credential is only ever used
    /// by a foreground capture on this device, so it needs neither background
    /// access before the first unlock nor a place in an iCloud/device backup.
    func write(_ value: String, account: String) {
        guard let data = value.data(using: .utf8) else { return }
        delete(account)
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
            kSecValueData as String: data,
            kSecAttrAccessible as String: kSecAttrAccessibleAfterFirstUnlockThisDeviceOnly,
        ]
        SecItemAdd(query as CFDictionary, nil)
    }

    func delete(_ account: String) {
        let query: [String: Any] = [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
        SecItemDelete(query as CFDictionary)
    }
}
#endif

/// Lock-guarded in-memory backing, injected by the tests (and the fallback on any
/// platform without `Security`).
final class HaviInMemoryCredentialBacking: HaviCredentialBacking, @unchecked Sendable {
    private let lock = NSLock()
    private var storage: [String: String] = [:]

    init() {}

    func read(_ account: String) -> String? {
        lock.lock(); defer { lock.unlock() }
        return storage[account]
    }

    func write(_ value: String, account: String) {
        lock.lock(); defer { lock.unlock() }
        storage[account] = value
    }

    func delete(_ account: String) {
        lock.lock(); defer { lock.unlock() }
        storage[account] = nil
    }
}
