import AppKit
import ImageIO
import XCTest
@testable import Valora

final class IndependentArtworkPreparationTests: XCTestCase {
    private func image(width: Int, height: Int, period: Int = 1) throws -> CGImage {
        var bytes = [UInt8](repeating: 255, count: width * height * 4)
        for y in 0..<height {
            for x in 0..<width {
                let c: UInt8 = ((x / period + y / period) % 2 == 0) ? 0 : 255
                for component in 0..<3 { bytes[(y * width + x) * 4 + component] = c }
            }
        }
        return try bytes.withUnsafeMutableBytes { buffer in
            let context = try XCTUnwrap(CGContext(
                data: buffer.baseAddress, width: width, height: height,
                bitsPerComponent: 8, bytesPerRow: width * 4,
                space: CGColorSpace(name: CGColorSpace.sRGB)!,
                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue))
            return try XCTUnwrap(context.makeImage())
        }
    }

    func testSmallArtworkHonorsExifOrientation() throws {
        let original = try image(width: 120, height: 60)
        let data = NSMutableData()
        let destination = try XCTUnwrap(CGImageDestinationCreateWithData(
            data, "public.tiff" as CFString, 1, nil))
        CGImageDestinationAddImage(destination, original,
                                  [kCGImagePropertyOrientation: 6] as CFDictionary)
        XCTAssertTrue(CGImageDestinationFinalize(destination))
        let source = try XCTUnwrap(CGImageSourceCreateWithData(data, nil))
        let properties = try XCTUnwrap(CGImageSourceCopyPropertiesAtIndex(source, 0, nil)
                                        as? [CFString: Any])
        XCTAssertEqual((properties[kCGImagePropertyOrientation] as? NSNumber)?.intValue, 6)
        let prepared = try XCTUnwrap(ArtworkImage.prepare(data as Data))
        XCTAssertEqual(prepared.size.width, 60)
        XCTAssertEqual(prepared.size.height, 120)
    }

    func testDifferentFineDetailArtworkHasDifferentIdentity() throws {
        let a = NSImage(cgImage: try image(width: 256, height: 256, period: 1),
                        size: NSSize(width: 256, height: 256))
        let b = NSImage(cgImage: try image(width: 256, height: 256, period: 2),
                        size: NSSize(width: 256, height: 256))
        XCTAssertNotEqual(ArtworkPalette.extract(a).identity, ArtworkPalette.extract(b).identity,
                          "different prepared pixels must not alias through a tiny identity thumbnail")
    }
}
