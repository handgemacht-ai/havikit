import Foundation
import XCTest
@testable import HaviKit

/// Credential persistence round-trip (design §5): a device-code session, its
/// display names, and the expiry survive store → read, `signIn` overwrites with
/// no names, and `clear` removes everything. Uses the in-memory backing so the
/// test never touches the real Keychain.
final class HaviTokenStoreTests: XCTestCase {
    private func makeStore() -> HaviTokenStore {
        HaviTokenStore(backing: HaviInMemoryCredentialBacking())
    }

    func testSessionRoundTrip() {
        let store = makeStore()
        let expiry = Date(timeIntervalSince1970: 1_800_000_000)
        store.store(HaviConnectedSession(
            accessToken: "tok",
            workspaceID: "ws",
            refreshToken: nil,
            expiresAt: expiry,
            userName: "marco@alimax.at",
            workspaceName: "Team HAVI"
        ))

        XCTAssertTrue(store.hasCredential)
        XCTAssertEqual(store.accessToken, "tok")
        XCTAssertEqual(store.workspaceID, "ws")
        XCTAssertEqual(store.userName, "marco@alimax.at")
        XCTAssertEqual(store.workspaceName, "Team HAVI")
        XCTAssertNil(store.refreshToken)
        XCTAssertEqual(store.expiresAt?.timeIntervalSince1970 ?? 0, expiry.timeIntervalSince1970, accuracy: 0.001)

        let session = store.connectedSession
        XCTAssertEqual(session?.accessToken, "tok")
        XCTAssertEqual(session?.userName, "marco@alimax.at")
        XCTAssertEqual(session?.workspaceName, "Team HAVI")
    }

    func testSignInStoresBareCredentialAndClearsNames() {
        let store = makeStore()
        store.store(HaviConnectedSession(
            accessToken: "old",
            workspaceID: "wsOld",
            userName: "old@user",
            workspaceName: "Old Team"
        ))

        store.signIn(token: "new", workspaceID: "wsNew")

        XCTAssertEqual(store.accessToken, "new")
        XCTAssertEqual(store.workspaceID, "wsNew")
        XCTAssertNil(store.userName)
        XCTAssertNil(store.workspaceName)
        XCTAssertNil(store.expiresAt)
    }

    func testClearRemovesEverything() {
        let store = makeStore()
        store.store(HaviConnectedSession(
            accessToken: "tok",
            workspaceID: "ws",
            userName: "u",
            workspaceName: "w"
        ))

        store.clear()

        XCTAssertFalse(store.hasCredential)
        XCTAssertNil(store.accessToken)
        XCTAssertNil(store.workspaceID)
        XCTAssertNil(store.userName)
        XCTAssertNil(store.workspaceName)
        XCTAssertNil(store.connectedSession)
    }
}
