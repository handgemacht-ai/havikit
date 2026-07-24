import Foundation

/// Immutable value handed to `HaviUploader` on submit (design §1). Carries the
/// assembled envelope JSON string, the encoded screenshot, the load-bearing
/// multipart siblings, the snapshotted credential, and a reencoder over the
/// cropped, redacted outgoing image for the server-driven fallbacks — nothing
/// mutable, so a
/// later context/tag mutation or credential change cannot race an in-flight send.
///
/// `idempotencyKey` is minted once per pending annotation and rides on every send
/// of it — the transient retry and both re-encode fallbacks — so a request that
/// timed out after the server had already stored it cannot become a duplicate
/// annotation.
public struct PendingAnnotation: Sendable {
    public let annotationJSON: String
    public let imageData: Data?
    public let imageFormat: HaviImageFormat
    public let siblings: [String: String]
    public let workspaceID: String?
    public let bearerToken: String?
    public let reencoder: HaviImageReencoder?
    public let idempotencyKey: String

    public init(
        annotationJSON: String,
        imageData: Data?,
        imageFormat: HaviImageFormat,
        siblings: [String: String],
        workspaceID: String?,
        bearerToken: String? = nil,
        reencoder: HaviImageReencoder? = nil,
        idempotencyKey: String = UUID().uuidString
    ) {
        self.annotationJSON = annotationJSON
        self.imageData = imageData
        self.imageFormat = imageFormat
        self.siblings = siblings
        self.workspaceID = workspaceID
        self.bearerToken = bearerToken
        self.reencoder = reencoder
        self.idempotencyKey = idempotencyKey
    }

    /// Assembles the pending annotation from a builder input plus encoded image
    /// bytes. The envelope, siblings, and format come straight from the builder;
    /// the credential + reencoder are snapshotted from the runtime at submit time.
    public static func make(
        input: HaviEnvelopeInput,
        imageData: Data?,
        imageFormat: HaviImageFormat,
        workspaceID: String?,
        bearerToken: String? = nil,
        reencoder: HaviImageReencoder? = nil
    ) throws -> PendingAnnotation {
        PendingAnnotation(
            annotationJSON: try HaviEnvelopeBuilder.jsonString(input),
            imageData: imageData,
            imageFormat: imageFormat,
            siblings: HaviEnvelopeBuilder.siblings(input),
            workspaceID: workspaceID,
            bearerToken: bearerToken,
            reencoder: reencoder
        )
    }
}
