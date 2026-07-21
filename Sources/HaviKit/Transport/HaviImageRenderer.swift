#if canImport(UIKit)
import UIKit

/// Renders the frozen snapshot to downscaled PNG/JPEG bytes (design §2, §4). The
/// longest side is capped at 1600 px with the retina multiplier dropped
/// (`format.scale = 1`); if the encoded bytes exceed the format cap the longest
/// side steps down the ladder and re-encodes. Coordinates in the envelope are
/// always computed in this downscaled pixel space, so markup lines up regardless
/// of format. iOS-only; the pure size math lives in `HaviImagePlan` so it runs
/// in tests without a Simulator.
enum HaviImageRenderer {
    static let jpegQuality: CGFloat = 0.7

    /// Encodes at the largest ladder size whose bytes fit under `maxBytes`,
    /// falling back to the floor size when even that is over (the server
    /// backstops with `payload_too_large`).
    static func encode(_ image: UIImage, format: HaviImageFormat, maxBytes: Int) -> Data? {
        for side in HaviImagePlan.stepDownLadder {
            if let data = render(image, format: format, maxLongestSide: side), data.count <= maxBytes {
                return data
            }
        }
        return render(image, format: format, maxLongestSide: HaviImagePlan.stepDownLadder.last ?? HaviImagePlan.defaultMaxLongestSide)
    }

    static func render(_ image: UIImage, format: HaviImageFormat, maxLongestSide: Int) -> Data? {
        renderWithSize(image, format: format, maxLongestSide: maxLongestSide)?.data
    }

    /// Like `encode`, but also returns the **downscaled pixel size** so the
    /// capture model can project the markup rectangle into the exact image space
    /// the screenshot is encoded in (design §3, §4).
    static func encodeWithSize(_ image: UIImage, format: HaviImageFormat, maxBytes: Int) -> (data: Data, size: HaviSize)? {
        for side in HaviImagePlan.stepDownLadder {
            if let result = renderWithSize(image, format: format, maxLongestSide: side), result.data.count <= maxBytes {
                return result
            }
        }
        return renderWithSize(image, format: format, maxLongestSide: HaviImagePlan.stepDownLadder.last ?? HaviImagePlan.defaultMaxLongestSide)
    }

    static func renderWithSize(_ image: UIImage, format: HaviImageFormat, maxLongestSide: Int) -> (data: Data, size: HaviSize)? {
        let target = HaviImagePlan.targetSize(
            width: Int(image.size.width.rounded()),
            height: Int(image.size.height.rounded()),
            maxLongestSide: maxLongestSide
        )
        let rendererFormat = UIGraphicsImageRendererFormat.default()
        rendererFormat.scale = 1
        rendererFormat.opaque = false
        let renderer = UIGraphicsImageRenderer(
            size: CGSize(width: target.width, height: target.height),
            format: rendererFormat
        )
        let scaled = renderer.image { _ in
            image.draw(in: CGRect(x: 0, y: 0, width: target.width, height: target.height))
        }
        let data: Data?
        switch format {
        case .png:
            data = scaled.pngData()
        case .jpeg:
            data = scaled.jpegData(compressionQuality: jpegQuality)
        }
        guard let data else { return nil }
        return (data, target)
    }

    /// A reencoder over `image` for the uploader's fallback paths (design §4).
    static func reencoder(for image: UIImage) -> HaviImageReencoder {
        HaviImageReencoder { format, maxLongestSide in
            render(image, format: format, maxLongestSide: maxLongestSide)
        }
    }
}
#endif
