import AppKit
import ImageIO

/// Bounded artwork preparation for the 56pt cover.
///
/// The real display input is 56pt; at the current 2x backing scale that is
/// 112px. 256px leaves margin for 3x/non-square sources without retaining the
/// original full-size decoded image. Larger sources are downsampled from the
/// compressed bytes with ImageIO, never by decoding the full image first.
enum ArtworkImage {
    static let maxPixel = 256

    static func prepare(_ data: Data, maxPixel: Int = ArtworkImage.maxPixel) -> NSImage? {
        guard !data.isEmpty, maxPixel > 0,
              let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let limit = max(1, maxPixel)
        let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any]
        let width = (properties?[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue ?? 0
        let height = (properties?[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue ?? 0
        let orientation = (properties?[kCGImagePropertyOrientation] as? NSNumber)?.intValue ?? 1
        var cg: CGImage?
        if orientation == 1, width > 0, height > 0, max(width, height) <= limit {
            // Ordinary small source: no upscale and no thumbnail interpolation.
            cg = CGImageSourceCreateImageAtIndex(source, 0, nil)
        } else {
            // Any non-1 EXIF orientation must go through ImageIO's transform
            // path, including small images. The budget is capped by the source
            // longest side so small images are never enlarged.
            let thumbnailLimit = width > 0 && height > 0
                ? min(limit, max(width, height)) : limit
            let options: [CFString: Any] = [
                kCGImageSourceCreateThumbnailFromImageAlways: true,
                kCGImageSourceCreateThumbnailWithTransform: true,
                kCGImageSourceShouldCacheImmediately: false,
                kCGImageSourceThumbnailMaxPixelSize: thumbnailLimit
            ]
            cg = CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
        }
        guard let cg else { return nil }
        return NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
    }
}
