import AppKit
import CryptoKit

/// Bounded local palette extraction. The original's dominant-color selection
/// algorithm is not yet reproduced; its progress style and white-filter rule are.
enum ArtworkPalette {
    /// Identity is the complete bounded prepared bitmap (at most 256px on
    /// its longest side), not the 32x32 palette and not the original encoded
    /// bytes. Re-encoding the same rendered cover keeps the same ID; fine
    /// checkerboard/detail differences cannot collapse through a tiny digest.
    private static let identityBudget = ArtworkImage.maxPixel

    static func extract(_ image: NSImage?) -> (identity: String, colors: [NSColor]) {
        guard let image else { return ("", []) }
        var bounds = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &bounds, context: nil, hints: nil) else {
            return ("", [])
        }
        let identity = pixelIdentity(cg)
        let size = 32
        var pixels = [UInt8](repeating: 0, count: size * size * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: size, height: size,
                bitsPerComponent: 8, bytesPerRow: size * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cg, in: CGRect(x: 0, y: 0, width: size, height: size))
            return true
        }
        guard rendered else { return (identity, []) }
        var buckets: [Int: (count: Int, r: Double, g: Double, b: Double)] = [:]
        for index in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[index+3]) / 255
            guard alpha > 0.5 else { continue }
            let r = min(1, Double(pixels[index]) / 255 / alpha)
            let g = min(1, Double(pixels[index+1]) / 255 / alpha)
            let b = min(1, Double(pixels[index+2]) / 255 / alpha)
            let key = Int(r * 7) * 64 + Int(g * 7) * 8 + Int(b * 7)
            let old = buckets[key] ?? (0, 0, 0, 0)
            buckets[key] = (old.count + 1, old.r + r, old.g + g, old.b + b)
        }
        let sorted = buckets.sorted {
            $0.value.count == $1.value.count ? $0.key < $1.key : $0.value.count > $1.value.count
        }
        var selected: [NSColor] = []
        for (_, bucket) in sorted {
            let n = Double(bucket.count)
            let r = bucket.r / n, g = bucket.g / n, b = bucket.b / n
            if selected.contains(where: {
                pow($0.redComponent - r, 2) + pow($0.greenComponent - g, 2)
                    + pow($0.blueComponent - b, 2) < 0.08
            }) { continue }
            selected.append(NSColor(srgbRed: r, green: g, blue: b, alpha: 1))
            if selected.count == 4 { break }
        }
        return (identity, selected)
    }

    private static func pixelIdentity(_ cg: CGImage) -> String {
        let budget = identityBudget
        let longest = max(cg.width, cg.height)
        let width: Int
        let height: Int
        if longest > budget {
            let scale = Double(budget) / Double(longest)
            width = max(1, Int((Double(cg.width) * scale).rounded()))
            height = max(1, Int((Double(cg.height) * scale).rounded()))
        } else {
            width = max(1, cg.width)
            height = max(1, cg.height)
        }
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data: bytes.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .high
            context.draw(cg, in: CGRect(x: 0, y: 0, width: width, height: height))
            return true
        }
        guard rendered else { return "" }
        // Exact stride, deterministic zero-initialized buffer, full bounded
        // pixels and dimensions. No TIFF serialization or original-size copy.
        var hasher = SHA256()
        withUnsafeBytes(of: UInt32(width).littleEndian) { hasher.update(bufferPointer: $0) }
        withUnsafeBytes(of: UInt32(height).littleEndian) { hasher.update(bufferPointer: $0) }
        pixels.withUnsafeBytes { hasher.update(bufferPointer: $0) }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }

    static func luminance(_ color: NSColor) -> Double {
        func linear(_ value:Double) -> Double { value <= 0.03928 ? value/12.92 : pow((value+0.055)/1.055,2.4) }
        return 0.2126*linear(color.redComponent)+0.7152*linear(color.greenComponent)+0.0722*linear(color.blueComponent)
    }
}
