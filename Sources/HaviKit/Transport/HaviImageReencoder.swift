import Foundation

/// A retained handle to the cropped, redacted outgoing image that can re-render
/// it to encoded bytes at a chosen format + longest side. It rides on
/// `PendingAnnotation` so the uploader can execute the two server-driven
/// re-encode fallbacks (design §4) — `unsupported_media_type` → PNG,
/// `payload_too_large` → 1024 px — without the actor ever touching UIKit. SDK-4
/// builds one over the cropped, redacted outgoing image
/// (`HaviImageRenderer.reencoder`); transport tests inject a stub.
///
/// `@unchecked Sendable`: the closure captures a `UIImage` (not `Sendable`), but
/// the snapshot is immutable once frozen and read-only here, so it is safe to
/// hand across the actor boundary.
public struct HaviImageReencoder: @unchecked Sendable {
    let encode: (HaviImageFormat, Int) -> Data?

    public init(_ encode: @escaping (HaviImageFormat, Int) -> Data?) {
        self.encode = encode
    }

    func callAsFunction(_ format: HaviImageFormat, _ maxLongestSide: Int) -> Data? {
        encode(format, maxLongestSide)
    }
}
