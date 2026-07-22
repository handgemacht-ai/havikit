#if canImport(UIKit)
import UIKit

/// Performs the real byte crop (bead havi-oukr) before any bytes leave the
/// device: pixels outside the crop rect are never drawn into the returned
/// image, the same privacy posture as `HaviImageRedactor`'s opaque burn. Runs
/// on the full-resolution freeze snapshot, **before** redaction and encoding,
/// so every downstream step (burn, downscale/encode, and the uploader's
/// re-encode fallbacks) only ever sees the cropped canvas.
enum HaviImageCropper {
    /// Returns a copy of `image` containing only the pixels inside `normalizedRect`
    /// (0…1, full-image space). Returns `image` unchanged when the rect is the
    /// full frame or degenerates to less than a pixel.
    static func crop(_ image: UIImage, to normalizedRect: CGRect) -> UIImage {
        guard normalizedRect != HaviCropGeometry.fullFrame else { return image }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }

        let clamped = HaviCropGeometry.clamped(normalizedRect)
        let pixelRect = CGRect(
            x: clamped.minX * size.width,
            y: clamped.minY * size.height,
            width: clamped.width * size.width,
            height: clamped.height * size.height
        )
        guard pixelRect.width >= 1, pixelRect.height >= 1 else { return image }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = true

        return UIGraphicsImageRenderer(size: pixelRect.size, format: format).image { _ in
            image.draw(at: CGPoint(x: -pixelRect.minX, y: -pixelRect.minY))
        }
    }
}
#endif
