import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import HaviKit

/// The workspace label vocabulary path (bead havi-jj51): parsing the
/// `GET /api/label-definitions` envelope into renderable definitions, and the
/// best-effort fetch that degrades to `nil` on any failure so capture is never
/// blocked. All network is against the stubbed `URLProtocol`.
final class HaviLabelServiceTests: XCTestCase {
    private static let vocabularyJSON = """
    {
      "data": [
        { "id": "id-flag", "key": "regression", "name": "Regression", "kind": "flag",
          "allowed_values": [], "color": null, "description": null, "position": 2 },
        { "id": "id-priority", "key": "priority", "name": "Priority", "kind": "choice",
          "allowed_values": ["high", "medium", "low"], "color": null, "description": null, "position": 0 },
        { "id": "id-area", "key": "area", "name": "Area", "kind": "value",
          "allowed_values": [], "color": "#0A84FF", "description": "Feature area", "position": 1 }
      ]
    }
    """

    // MARK: - Parsing

    func testParsesAndSortsByPosition() throws {
        let defs = try XCTUnwrap(HaviLabelDefinition.parseList(Data(Self.vocabularyJSON.utf8)))
        XCTAssertEqual(defs.map(\.key), ["priority", "area", "regression"])

        let priority = defs[0]
        XCTAssertEqual(priority.kind, .choice)
        XCTAssertEqual(priority.allowedValues, ["high", "medium", "low"])
        XCTAssertEqual(priority.name, "Priority")

        let area = defs[1]
        XCTAssertEqual(area.kind, .value)
        XCTAssertEqual(area.color, "#0A84FF")
        XCTAssertEqual(area.description, "Feature area")

        XCTAssertEqual(defs[2].kind, .flag)
    }

    func testDropsArchivedUnknownKindAndEmptyChoice() throws {
        let json = """
        {
          "data": [
            { "id": "a", "key": "keep", "name": "Keep", "kind": "flag", "allowed_values": [], "position": 0 },
            { "id": "b", "key": "gone", "name": "Gone", "kind": "flag", "allowed_values": [], "position": 1, "archived": true },
            { "id": "c", "key": "future", "name": "Future", "kind": "matrix", "allowed_values": [], "position": 2 },
            { "id": "d", "key": "emptychoice", "name": "Bad", "kind": "choice", "allowed_values": [], "position": 3 },
            { "id": "e", "key": "", "name": "NoKey", "kind": "flag", "allowed_values": [], "position": 4 }
          ]
        }
        """
        let defs = try XCTUnwrap(HaviLabelDefinition.parseList(Data(json.utf8)))
        XCTAssertEqual(defs.map(\.key), ["keep"])
    }

    func testMalformedEnvelopeReturnsNil() {
        XCTAssertNil(HaviLabelDefinition.parseList(Data("not json".utf8)))
        XCTAssertNil(HaviLabelDefinition.parseList(Data(#"{"nope": []}"#.utf8)))
    }

    func testEmptyVocabularyParsesToEmptyList() throws {
        let defs = try XCTUnwrap(HaviLabelDefinition.parseList(Data(#"{"data": []}"#.utf8)))
        XCTAssertEqual(defs, [])
    }

    // MARK: - Fetch

    private func makeService() -> HaviLabelService {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let config = HaviConfig(
            isEnabled: true,
            baseURL: URL(string: "https://havi.example"),
            workspaceID: nil,
            project: nil,
            worktree: nil,
            branch: nil,
            commit: nil,
            imageFormat: .png,
            devToken: nil,
            redaction: HaviRedactionPolicy()
        )
        return HaviLabelService(config: config, session: session)
    }

    func testFetchReturnsParsedDefinitionsOn200() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(status: 200, json: Self.vocabularyJSON)

        let defs = await makeService().fetch(token: "tok", workspaceID: "ws")
        XCTAssertEqual(defs?.map(\.key), ["priority", "area", "regression"])
    }

    func testFetchReturnsNilOnAuthError() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(status: 401, json: #"{"error":{"code":"unauthorized"}}"#)

        let defs = await makeService().fetch(token: "tok", workspaceID: "ws")
        XCTAssertNil(defs)
    }

    func testFetchReturnsNilOnTransportFailure() async {
        StubURLProtocol.reset() // nothing enqueued -> stub fails the request

        let defs = await makeService().fetch(token: "tok", workspaceID: "ws")
        XCTAssertNil(defs)
    }

    func testFetchWithoutCredentialShortCircuitsToNil() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(status: 200, json: Self.vocabularyJSON)

        let defs = await makeService().fetch(token: "", workspaceID: "ws")
        XCTAssertNil(defs)
        XCTAssertEqual(StubURLProtocol.consumedCount, 0, "no request is made without a token")
    }
}
