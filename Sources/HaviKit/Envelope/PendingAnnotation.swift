import Foundation

/// Immutable value handed to `HaviUploader` on submit (design §1). Carries the
/// assembled envelope JSON string, the encoded screenshot, the load-bearing
/// multipart siblings, and the workspace id — nothing mutable, so a later
/// context/tag mutation cannot race an in-flight send.
public struct PendingAnnotation: Sendable {
    public let annotationJSON: String
    public let imageData: Data?
    public let imageFormat: HaviImageFormat
    public let siblings: [String: String]
    public let workspaceID: String?

    public init(
        annotationJSON: String,
        imageData: Data?,
        imageFormat: HaviImageFormat,
        siblings: [String: String],
        workspaceID: String?
    ) {
        self.annotationJSON = annotationJSON
        self.imageData = imageData
        self.imageFormat = imageFormat
        self.siblings = siblings
        self.workspaceID = workspaceID
    }

    /// Assembles the pending annotation from a builder input plus encoded image
    /// bytes. The envelope, siblings, and format come straight from the builder.
    public static func make(
        input: HaviEnvelopeInput,
        imageData: Data?,
        imageFormat: HaviImageFormat,
        workspaceID: String?
    ) throws -> PendingAnnotation {
        PendingAnnotation(
            annotationJSON: try HaviEnvelopeBuilder.jsonString(input),
            imageData: imageData,
            imageFormat: imageFormat,
            siblings: HaviEnvelopeBuilder.siblings(input),
            workspaceID: workspaceID
        )
    }
}
