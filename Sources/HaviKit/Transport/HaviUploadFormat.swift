import Foundation

/// The multipart `image` part descriptor and local byte cap per image format
/// (design §4). PNG is the ship default (the live backend is PNG-only, 2 MiB);
/// JPEG (quality 0.7, 5 MiB) becomes the default once BE-1 is verified, flipped
/// by the stamped `HAVI_IMAGE_FORMAT` flag with no code fork.
extension HaviImageFormat {
    var multipartFilename: String {
        self == .png ? "screenshot.png" : "screenshot.jpg"
    }

    var multipartContentType: String {
        self == .png ? "image/png" : "image/jpeg"
    }

    /// Conservative local cap the renderer targets before the server backstops
    /// with `payload_too_large`: the un-patched backend's 2 MiB for PNG, the
    /// raised 5 MiB for JPEG.
    var maxUploadBytes: Int {
        self == .png ? 2_097_152 : 5_242_880
    }
}
