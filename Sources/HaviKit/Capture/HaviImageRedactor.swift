#if canImport(UIKit)
import UIKit

/// Burns the user's `blur` redaction marks into the screenshot **pixels** before
/// any bytes leave the device (bead havi-6953). This app is a children's app, so
/// redaction is destructive and pre-byte, matching the snapshotter's default
/// text-field mask: each region is pixelated (a heavy mosaic), not merely blurred,
/// so the original content is unrecoverable from the uploaded image.
///
/// Runs on the full-resolution freeze snapshot, before `HaviImageRenderer`
/// downscales/encodes and before the uploader's re-encode fallbacks — so every
/// byte path (initial send and every fallback) sees the redacted pixels.
enum HaviImageRedactor {
    /// Blocks across a redacted region's longest side — smaller means coarser.
    static let mosaicBlocks: CGFloat = 10

    /// Returns a copy of `image` with each normalized (0…1) rect pixelated. When
    /// there are no rects the original image is returned unchanged.
    static func burn(blurRects normalizedRects: [CGRect], into image: UIImage) -> UIImage {
        guard !normalizedRects.isEmpty else { return image }
        let size = image.size
        guard size.width > 0, size.height > 0 else { return image }

        let format = UIGraphicsImageRendererFormat.default()
        format.scale = image.scale
        format.opaque = true

        return UIGraphicsImageRenderer(size: size, format: format).image { context in
            image.draw(in: CGRect(origin: .zero, size: size))
            let cgContext = context.cgContext
            for normalized in normalizedRects {
                let region = pixelRect(for: normalized, in: size)
                guard region.width >= 1, region.height >= 1 else { continue }
                pixelate(image, region: region, into: cgContext)
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

    /// Downscales `region` to a tiny grid, then draws it back over the region with
    /// interpolation off — a blocky mosaic that destroys the underlying detail.
    private static func pixelate(_ image: UIImage, region: CGRect, into context: CGContext) {
        let longest = max(region.width, region.height)
        let blocks = max(1, min(mosaicBlocks, longest))
        let tiny = CGSize(
            width: max(1, (region.width / longest * blocks).rounded()),
            height: max(1, (region.height / longest * blocks).rounded())
        )

        let tinyFormat = UIGraphicsImageRendererFormat.default()
        tinyFormat.scale = 1
        tinyFormat.opaque = true
        let mosaic = UIGraphicsImageRenderer(size: tiny, format: tinyFormat).image { _ in
            // Draw the source region into the tiny canvas: offset so `region`'s
            // top-left maps to the tiny origin, scaled down to the block grid.
            let scaleX = tiny.width / region.width
            let scaleY = tiny.height / region.height
            image.draw(in: CGRect(
                x: -region.minX * scaleX,
                y: -region.minY * scaleY,
                width: image.size.width * scaleX,
                height: image.size.height * scaleY
            ))
        }

        context.saveGState()
        context.clip(to: region)
        context.interpolationQuality = .none
        mosaic.draw(in: region)
        context.restoreGState()
    }
}
#endif
