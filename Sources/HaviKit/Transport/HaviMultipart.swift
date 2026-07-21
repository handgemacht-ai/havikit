import Foundation

/// Assembles the `multipart/form-data` body for `POST /api/annotations`
/// (design §4), matching the controller exactly: the `annotation` JSON field,
/// then the load-bearing siblings `project` / `worktree` / `branch` (only those
/// the controller reads, only when present), then the `image` file part last.
/// `commit` is deliberately not a sibling — it rides in `x:havi.dev` only.
enum HaviMultipart {
    static let siblingOrder = ["project", "worktree", "branch"]

    static func boundary() -> String {
        "havi.boundary.\(UUID().uuidString)"
    }

    static func body(
        boundary: String,
        annotationJSON: String,
        imageData: Data?,
        imageFilename: String,
        imageContentType: String,
        siblings: [String: String]
    ) -> Data {
        var data = Data()

        data.appendField(boundary: boundary, name: "annotation", value: annotationJSON)

        for key in siblingOrder {
            if let value = siblings[key] {
                data.appendField(boundary: boundary, name: key, value: value)
            }
        }

        if let imageData {
            data.appendString("--\(boundary)\r\n")
            data.appendString("Content-Disposition: form-data; name=\"image\"; filename=\"\(imageFilename)\"\r\n")
            data.appendString("Content-Type: \(imageContentType)\r\n\r\n")
            data.append(imageData)
            data.appendString("\r\n")
        }

        data.appendString("--\(boundary)--\r\n")
        return data
    }
}

private extension Data {
    mutating func appendString(_ string: String) {
        if let encoded = string.data(using: .utf8) {
            append(encoded)
        }
    }

    mutating func appendField(boundary: String, name: String, value: String) {
        appendString("--\(boundary)\r\n")
        appendString("Content-Disposition: form-data; name=\"\(name)\"\r\n\r\n")
        appendString(value)
        appendString("\r\n")
    }
}
