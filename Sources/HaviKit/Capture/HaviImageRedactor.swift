#if canImport(UIKit)
import UIKit

/// Burns the user's `blur` redaction marks into the screenshot **pixels** before
/// any bytes leave the device (bead havi-6953). This app is a children's app, so
/// redaction is destructive and pre-byte, matching the snapshotter's default
/// text-field mask: each region is filled with **opaque black**, not merely
/// blurred or pixelated, so the original content is unrecoverable from the
/// uploaded image.
///
/// Runs on the full-resolution freeze snapshot, before `HaviImageRenderer`
/// downscales/encodes and before the uploader's re-encode fallbacks — so every
/// byte path (initial send and every fallback) sees the redacted pixels.
enum HaviImageRedactor {
    /// Returns a copy of `image` with each normalized (0…1) rect filled with
    /// opaque black. When there are no rects the original image is returned
    /// unchanged.
    static func burn(blurRects normalizedRects: [CGRect], into image: UIImage) -> UIImage {
        guard !normalizedRects.isEmpty else { return image }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            image.draw(in: CGRect(origin: .zero, size: size))
            UIColor.black.setFill()
            for normalized in normalizedRects {
                let region = pixelRect(for: normalized, in: size)
                guard region.width >= 1, region.height >= 1 else { continue }
                context.fill(region)
            }
        }
    }

    private static func pixelRect(for normalized: CGRect, in size: CGSize) -> CGRect {
        let standardized = normalized.standardized
        return CGRect(
            x: standardized.minX * size.width,
            y: standardized.minY * size.height,
            width: standardized.width * size.width,
            height: standardized.height * size.height
        ).integral.intersection(CGRect(origin: .zero, size: size))
    }
}
#endif
