import XCTest
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
@testable import HaviKit

/// Transport tests (design §4, §10): multipart part names + siblings, image
/// format descriptors, downscale planner math, `error.code` mapping (including
/// the `unsupported_media_type` → PNG re-encode fallback and the transient
/// retry), all against a stubbed `URLProtocol` so nothing touches the network.
final class HaviTransportTests: XCTestCase {
    // MARK: - Multipart assembly

    func testMultipartCarriesAnnotationSiblingsAndImageLast() {
        let body = HaviMultipart.body(
            boundary: "B",
            annotationJSON: "{\"type\":\"Annotation\"}",
            imageData: Data("PNGBYTES".utf8),
            imageFilename: "screenshot.png",
            imageContentType: "image/png",
            siblings: ["project": "lesewerkstatt", "worktree": "wt", "branch": "br", "commit": "deadbee"]
        )
        let text = String(decoding: body, as: UTF8.self)

        XCTAssertTrue(text.contains("name=\"annotation\"\r\n\r\n{\"type\":\"Annotation\"}"))
        XCTAssertTrue(text.contains("name=\"project\"\r\n\r\nlesewerkstatt"))
        XCTAssertTrue(text.contains("name=\"worktree\"\r\n\r\nwt"))
        XCTAssertTrue(text.contains("name=\"branch\"\r\n\r\nbr"))
        XCTAssertTrue(text.contains("name=\"image\"; filename=\"screenshot.png\""))
        XCTAssertTrue(text.contains("Content-Type: image/png"))
        XCTAssertTrue(text.hasSuffix("--B--\r\n"))
        // commit is never a sibling — it rides only in x:havi.dev.
        XCTAssertFalse(text.contains("name=\"commit\""))
        // image part is last: it comes after every field.
        let imageIndex = text.range(of: "name=\"image\"")!.lowerBound
        for field in ["annotation", "project", "worktree", "branch"] {
            XCTAssertLessThan(text.range(of: "name=\"\(field)\"")!.lowerBound, imageIndex)
        }
    }

    func testMultipartOmitsAbsentSiblingsAndImage() {
        let body = HaviMultipart.body(
            boundary: "B",
            annotationJSON: "{}",
            imageData: nil,
            imageFilename: "screenshot.png",
            imageContentType: "image/png",
            siblings: ["project": "lesewerkstatt"]
        )
        let text = String(decoding: body, as: UTF8.self)
        XCTAssertTrue(text.contains("name=\"project\""))
        XCTAssertFalse(text.contains("name=\"worktree\""))
        XCTAssertFalse(text.contains("name=\"branch\""))
        XCTAssertFalse(text.contains("name=\"image\""))
    }

    // MARK: - Image format descriptors

    func testImageFormatDescriptors() {
        XCTAssertEqual(HaviImageFormat.png.multipartFilename, "screenshot.png")
        XCTAssertEqual(HaviImageFormat.png.multipartContentType, "image/png")
        XCTAssertEqual(HaviImageFormat.png.maxUploadBytes, 2_097_152)
        XCTAssertEqual(HaviImageFormat.jpeg.multipartFilename, "screenshot.jpg")
        XCTAssertEqual(HaviImageFormat.jpeg.multipartContentType, "image/jpeg")
        XCTAssertEqual(HaviImageFormat.jpeg.maxUploadBytes, 5_242_880)
    }

    // MARK: - Downscale planner

    func testDownscaleScaleAndTargetSize() {
        XCTAssertEqual(HaviImagePlan.scale(width: 3000, height: 2000, maxLongestSide: 1600), 1600.0 / 3000.0, accuracy: 1e-9)
        XCTAssertEqual(HaviImagePlan.scale(width: 800, height: 600, maxLongestSide: 1600), 1.0)

        let target = HaviImagePlan.targetSize(width: 3000, height: 2000, maxLongestSide: 1600)
        XCTAssertEqual(target.width, 1600)
        XCTAssertEqual(target.height, 1067)

        let small = HaviImagePlan.targetSize(width: 800, height: 600, maxLongestSide: 1600)
        XCTAssertEqual(small, HaviSize(width: 800, height: 600))
    }

    func testDownscaleLadderSteps() {
        XCTAssertEqual(HaviImagePlan.nextStepDown(below: 1600), 1280)
        XCTAssertEqual(HaviImagePlan.nextStepDown(below: 1280), 1024)
        XCTAssertEqual(HaviImagePlan.nextStepDown(below: 1024), 900)
        XCTAssertNil(HaviImagePlan.nextStepDown(below: 900))
        XCTAssertEqual(HaviImagePlan.payloadTooLargeLongestSide, 1024)
    }

    // MARK: - Error mapping table

    func testErrorCodeMapping() {
        XCTAssertEqual(HaviErrorMapping.mapCode("unauthorized").action, .reauth)
        XCTAssertEqual(HaviErrorMapping.mapCode("missing_workspace_id").action, .reauth)
        XCTAssertEqual(HaviErrorMapping.mapCode("invalid_workspace_id").action, .reauth)
        XCTAssertEqual(HaviErrorMapping.mapCode("workspace_not_found").action, .reauth)
        XCTAssertEqual(HaviErrorMapping.mapCode("forbidden").action, .terminal)
        XCTAssertEqual(HaviErrorMapping.mapCode("unsupported_media_type").action, .reencodePNG)
        XCTAssertEqual(HaviErrorMapping.mapCode("payload_too_large").action, .reencodeSmaller)
        XCTAssertEqual(HaviErrorMapping.mapCode("validation_error").action, .terminal)
        XCTAssertEqual(HaviErrorMapping.mapCode("storage_error").action, .transientRetry)
        XCTAssertEqual(HaviErrorMapping.mapCode("not_found").action, .terminal)
        XCTAssertEqual(HaviErrorMapping.mapCode("something_new").action, .terminal)
    }

    func testResponseClassification() {
        if case .success(let id) = HaviErrorMapping.classify(status: 201, body: Data("{\"data\":{\"id\":\"abc\"}}".utf8)) {
            XCTAssertEqual(id, "abc")
        } else {
            XCTFail("expected success")
        }

        let mapped = HaviErrorMapping.classify(status: 422, body: Data("{\"error\":{\"code\":\"validation_error\"}}".utf8))
        XCTAssertEqual(mapped, .mapped(HaviErrorMapping.mapCode("validation_error")))

        // Non-JSON 5xx → transient; non-JSON 4xx → terminal.
        XCTAssertEqual(HaviErrorMapping.classify(status: 503, body: Data("gateway".utf8)), .mapped(HaviErrorMapping.transientTransport))
        if case .mapped(let e) = HaviErrorMapping.classify(status: 400, body: Data("nope".utf8)) {
            XCTAssertEqual(e.action, .terminal)
        } else {
            XCTFail("expected terminal")
        }
    }

    // MARK: - End-to-end submit over a stubbed URLProtocol

    private func makeUploader() -> HaviUploader {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [StubURLProtocol.self]
        let session = URLSession(configuration: configuration)
        let config = HaviConfig(
            isEnabled: true,
            baseURL: URL(string: "https://havi.example.test")!,
            workspaceID: "ws-1",
            project: "lesewerkstatt",
            worktree: "wt",
            branch: "br",
            commit: "c0ffee",
            imageFormat: .png,
            devToken: "dev-token",
            redaction: HaviRedactionPolicy()
        )
        return HaviUploader(config: config, session: session, retryDelayNanoseconds: 0)
    }

    private func pending(format: HaviImageFormat = .png, token: String? = "tkn", workspace: String? = "ws-1") -> PendingAnnotation {
        PendingAnnotation(
            annotationJSON: "{\"type\":\"Annotation\"}",
            imageData: Data("PNG".utf8),
            imageFormat: format,
            siblings: ["project": "lesewerkstatt", "worktree": "wt", "branch": "br"],
            workspaceID: workspace,
            bearerToken: token,
            reencoder: HaviImageReencoder { fmt, side in Data("re-\(fmt.rawValue)-\(side)".utf8) }
        )
    }

    func testSubmitSuccessSendsHeaders() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(status: 201, json: "{\"data\":{\"id\":\"anno-1\"}}")
        let result = await makeUploader().submit(pending())
        XCTAssertEqual(result, .success(id: "anno-1"))

        let request = StubURLProtocol.lastRequests.last
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Authorization"), "Bearer tkn")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "x-havi-workspace-id"), "ws-1")
        XCTAssertTrue(request?.value(forHTTPHeaderField: "Content-Type")?.hasPrefix("multipart/form-data; boundary=") ?? false)
        XCTAssertEqual(request?.url?.absoluteString, "https://havi.example.test/api/annotations")
    }

    func testUnsupportedMediaTypeRetriesAsPNGThenSucceeds() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(status: 415, json: "{\"error\":{\"code\":\"unsupported_media_type\"}}")
        StubURLProtocol.enqueue(status: 201, json: "{\"data\":{\"id\":\"anno-2\"}}")
        let result = await makeUploader().submit(pending(format: .jpeg))
        XCTAssertEqual(result, .success(id: "anno-2"))
        XCTAssertEqual(StubURLProtocol.consumedCount, 2)
    }

    func testUnsupportedMediaTypeRecursIsTerminal() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(status: 415, json: "{\"error\":{\"code\":\"unsupported_media_type\"}}")
        StubURLProtocol.enqueue(status: 415, json: "{\"error\":{\"code\":\"unsupported_media_type\"}}")
        let result = await makeUploader().submit(pending(format: .jpeg))
        if case .failure(let failure) = result {
            XCTAssertEqual(failure.kind, .terminal)
            XCTAssertEqual(failure.code, "unsupported_media_type")
        } else {
            XCTFail("expected terminal failure")
        }
    }

    func testStorageErrorRetriesOnceThenSucceeds() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(status: 503, json: "{\"error\":{\"code\":\"storage_error\"}}")
        StubURLProtocol.enqueue(status: 201, json: "{\"data\":{\"id\":\"anno-3\"}}")
        let result = await makeUploader().submit(pending())
        XCTAssertEqual(result, .success(id: "anno-3"))
    }

    func testValidationErrorIsTerminalNoRetry() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(status: 422, json: "{\"error\":{\"code\":\"validation_error\"}}")
        let result = await makeUploader().submit(pending())
        if case .failure(let failure) = result {
            XCTAssertEqual(failure.kind, .terminal)
        } else {
            XCTFail("expected terminal failure")
        }
        XCTAssertEqual(StubURLProtocol.consumedCount, 1)
    }

    func testUnauthorizedRoutesToReconnect() async {
        StubURLProtocol.reset()
        StubURLProtocol.enqueue(status: 401, json: "{\"error\":{\"code\":\"unauthorized\"}}")
        let result = await makeUploader().submit(pending())
        if case .failure(let failure) = result {
            XCTAssertEqual(failure.kind, .reconnect)
        } else {
            XCTFail("expected reconnect failure")
        }
    }

    func testNetworkFailureRetriesThenSurfacesRetry() async {
        StubURLProtocol.reset() // empty queue → the stub fails every attempt
        let result = await makeUploader().submit(pending())
        if case .failure(let failure) = result {
            XCTAssertEqual(failure.kind, .retry)
        } else {
            XCTFail("expected retry failure")
        }
        XCTAssertEqual(StubURLProtocol.consumedCount, 2) // one send + one in-memory retry
    }

    func testMissingCredentialReconnectsWithoutRequest() async {
        StubURLProtocol.reset()
        let result = await makeUploader().submit(pending(token: nil))
        if case .failure(let failure) = result {
            XCTAssertEqual(failure.kind, .reconnect)
        } else {
            XCTFail("expected reconnect failure")
        }
        XCTAssertEqual(StubURLProtocol.consumedCount, 0)
    }
}

/// In-memory `URLProtocol` stub: pops queued `(status, body)` responses FIFO and
/// records requests. When the queue is empty it fails the load so the transient
/// network path can be exercised.
final class StubURLProtocol: URLProtocol {
    private struct Stub { let status: Int; let body: Data }

    private static let lock = NSLock()
    nonisolated(unsafe) private static var queue: [Stub] = []
    nonisolated(unsafe) private static var requests: [URLRequest] = []
    nonisolated(unsafe) private static var consumed = 0

    static func reset() {
        lock.lock(); defer { lock.unlock() }
        queue = []
        requests = []
        consumed = 0
    }

    static func enqueue(status: Int, json: String) {
        lock.lock(); defer { lock.unlock() }
        queue.append(Stub(status: status, body: Data(json.utf8)))
    }

    static var consumedCount: Int {
        lock.lock(); defer { lock.unlock() }
        return consumed
    }

    static var lastRequests: [URLRequest] {
        lock.lock(); defer { lock.unlock() }
        return requests
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        StubURLProtocol.lock.lock()
        StubURLProtocol.requests.append(request)
        StubURLProtocol.consumed += 1
        let stub = StubURLProtocol.queue.isEmpty ? nil : StubURLProtocol.queue.removeFirst()
        StubURLProtocol.lock.unlock()

        guard let stub else {
            client?.urlProtocol(self, didFailWithError: URLError(.notConnectedToInternet))
            return
        }
        let response = HTTPURLResponse(
            url: request.url!,
            statusCode: stub.status,
            httpVersion: "HTTP/1.1",
            headerFields: ["Content-Type": "application/json"]
        )!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: stub.body)
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}
