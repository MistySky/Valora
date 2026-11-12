import AppKit
import ImageIO
import SwiftUI
import XCTest
import UniformTypeIdentifiers
@testable import Valora

@MainActor
final class ArtworkMemoryBoundedTests: XCTestCase {
    private func cgImage(width: Int, height: Int, color: NSColor,
                         alpha: CGFloat = 1) -> CGImage {
        let rgb = color.usingColorSpace(.sRGB) ?? color
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        context.setFillColor(CGColor(srgbRed: rgb.redComponent, green: rgb.greenComponent,
                                     blue: rgb.blueComponent, alpha: alpha))
        context.fill(CGRect(x: 0, y: 0, width: width, height: height))
        return context.makeImage()!
    }

    private func detailedImage(width: Int, height: Int) -> CGImage {
        let space = CGColorSpace(name: CGColorSpace.sRGB)!
        let context = CGContext(data: nil, width: width, height: height,
                                bitsPerComponent: 8, bytesPerRow: width * 4,
                                space: space,
                                bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)!
        let colors: [NSColor] = [.systemRed, .systemGreen, .systemBlue, .systemYellow,
                                 .systemPurple, .systemTeal]
        let block = max(8, width / 30)
        for y in stride(from: 0, to: height, by: block) {
            for x in stride(from: 0, to: width, by: block) {
                let index = ((x / block) + (y / block) * 3) % colors.count
                let color = colors[index].usingColorSpace(.sRGB)!
                context.setFillColor(CGColor(srgbRed: color.redComponent,
                                             green: color.greenComponent,
                                             blue: color.blueComponent, alpha: 1))
                context.fill(CGRect(x: x, y: y, width: block, height: block))
            }
        }
        return context.makeImage()!
    }

    private func encoded(_ image: CGImage, type: UTType, orientation: Int? = nil) -> Data? {
        let data = NSMutableData()
        guard let destination = CGImageDestinationCreateWithData(
            data, type.identifier as CFString, 1, nil) else { return nil }
        let properties: CFDictionary? = orientation.map {
            [kCGImagePropertyOrientation: $0] as CFDictionary
        }
        CGImageDestinationAddImage(destination, image, properties)
        guard CGImageDestinationFinalize(destination) else { return nil }
        return data as Data
    }

    private func dimensions(_ image: NSImage) -> (Int, Int) {
        var rect = CGRect(origin: .zero, size: image.size)
        guard let cg = image.cgImage(forProposedRect: &rect, context: nil, hints: nil) else {
            return (0, 0)
        }
        return (cg.width, cg.height)
    }

    func testLargeCoverIsBoundedBeforePaletteExtraction() throws {
        let source = cgImage(width: 3000, height: 3000, color: .systemRed)
        let png = try XCTUnwrap(encoded(source, type: .png))
        let prepared = try XCTUnwrap(ArtworkImage.prepare(png))
        let (width, height) = dimensions(prepared)
        XCTAssertLessThanOrEqual(max(width, height), ArtworkImage.maxPixel)
        XCTAssertGreaterThan(width, 0)
        XCTAssertEqual(width, height)
        let palette = ArtworkPalette.extract(prepared)
        XCTAssertFalse(palette.identity.isEmpty)
        XCTAssertFalse(palette.colors.isEmpty)
    }

    func testLargeCoverOneShotEstimateIsBounded() throws {
        let source = cgImage(width: 3000, height: 3000,
                             color: NSColor(srgbRed: 0.3, green: 0.4, blue: 0.8, alpha: 1))
        let png = try XCTUnwrap(encoded(source, type: .png))
        let oldImage = try XCTUnwrap(NSImage(data: png))
        var oldRect = CGRect(origin: .zero, size: oldImage.size)
        let oldCG = try XCTUnwrap(oldImage.cgImage(forProposedRect: &oldRect,
                                                  context: nil, hints: nil))
        let prepared = try XCTUnwrap(ArtworkImage.prepare(png))
        var newRect = CGRect(origin: .zero, size: prepared.size)
        let newCG = try XCTUnwrap(prepared.cgImage(forProposedRect: &newRect,
                                                   context: nil, hints: nil))
        let originalPixels = oldCG.width * oldCG.height
        let preparedPixels = newCG.width * newCG.height
        print("ARTWORK_EST compressed=\(png.count) originalPixels=\(originalPixels) " +
              "originalRGBA=\(originalPixels * 4) preparedPixels=\(preparedPixels) " +
              "preparedRGBA=\(preparedPixels * 4)")
        XCTAssertEqual(originalPixels, 9_000_000)
        XCTAssertLessThanOrEqual(max(newCG.width, newCG.height), ArtworkImage.maxPixel)
        XCTAssertLessThan(preparedPixels * 4, originalPixels * 4 / 100,
                          "the retained prepared bitmap must be a small fraction of the source")
    }

    func testAspectRatioIsPreservedAndSmallImagesAreNotUpscaled() throws {
        let small = try XCTUnwrap(encoded(cgImage(width: 120, height: 60, color: .systemBlue),
                                          type: .png))
        let smallImage = try XCTUnwrap(ArtworkImage.prepare(small))
        let smallSize = dimensions(smallImage)
        XCTAssertEqual(smallSize.0, 120)
        XCTAssertEqual(smallSize.1, 60)

        let large = try XCTUnwrap(encoded(cgImage(width: 1200, height: 600, color: .systemGreen),
                                          type: .png))
        let largeImage = try XCTUnwrap(ArtworkImage.prepare(large))
        let largeSize = dimensions(largeImage)
        XCTAssertLessThanOrEqual(max(largeSize.0, largeSize.1), ArtworkImage.maxPixel)
        XCTAssertEqual(Double(largeSize.0) / Double(largeSize.1), 2, accuracy: 0.02)
    }

    func testExifOrientationIsAppliedBeforeBounding() throws {
        let source = cgImage(width: 320, height: 160,
                             color: NSColor(srgbRed: 0.8, green: 0.2, blue: 0.1, alpha: 1))
        let jpeg = try XCTUnwrap(encoded(source, type: .jpeg, orientation: 6))
        let prepared = try XCTUnwrap(ArtworkImage.prepare(jpeg))
        let (width, height) = dimensions(prepared)
        XCTAssertLessThan(width, height,
                          "orientation 6 must present a portrait image, not the raw 2:1 landscape")
        XCTAssertLessThanOrEqual(max(width, height), ArtworkImage.maxPixel)
    }

    func testSameVisualDifferentLosslessEncodingKeepsIdentity() throws {
        let source = cgImage(width: 320, height: 180,
                             color: NSColor(srgbRed: 0.2, green: 0.6, blue: 0.9, alpha: 1))
        let png = try XCTUnwrap(encoded(source, type: .png))
        let tiff = try XCTUnwrap(encoded(source, type: .tiff))
        let first = ArtworkPalette.extract(try XCTUnwrap(ArtworkImage.prepare(png)))
        let second = ArtworkPalette.extract(try XCTUnwrap(ArtworkImage.prepare(tiff)))
        XCTAssertEqual(first.identity, second.identity)
        XCTAssertFalse(first.identity.isEmpty)
    }

    func testDifferentVisualsWithSameDominantColorDoNotAlias() throws {
        let redSquare = try XCTUnwrap(encoded(cgImage(width: 320, height: 320, color: .systemRed),
                                              type: .png))
        // Same solid color as the square but a different visual aspect/geometry.
        let redWide = try XCTUnwrap(encoded(cgImage(width: 320, height: 160, color: .systemRed),
                                            type: .png))
        let first = ArtworkPalette.extract(try XCTUnwrap(ArtworkImage.prepare(redSquare)))
        let second = ArtworkPalette.extract(try XCTUnwrap(ArtworkImage.prepare(redWide)))
        XCTAssertFalse(first.identity.isEmpty)
        XCTAssertFalse(second.identity.isEmpty)
        XCTAssertNotEqual(first.identity, second.identity)
        XCTAssertEqual(first.colors.first?.redComponent ?? 0,
                       second.colors.first?.redComponent ?? 1, accuracy: 0.02)
    }

    func test56ptRetinaArtworkStageIsVisuallyBounded() throws {
        let source = detailedImage(width: 1200, height: 1200)
        let data = try XCTUnwrap(encoded(source, type: .png))
        let old = try XCTUnwrap(NSImage(data: data))
        let bounded = try XCTUnwrap(ArtworkImage.prepare(data))

        func render(_ image: NSImage) -> NSBitmapImageRep? {
            let host = NSHostingView(rootView: Artwork(image: image, size: 56))
            host.frame = NSRect(x: 0, y: 0, width: 56, height: 56)
            let window = NSWindow(contentRect: host.frame, styleMask: .borderless,
                                  backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.contentView = host
            window.orderFrontRegardless()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))
            defer { window.close() }
            guard let rep = host.bitmapImageRepForCachingDisplay(in: host.bounds) else { return nil }
            host.cacheDisplay(in: host.bounds, to: rep)
            return rep
        }
        let oldRep = try XCTUnwrap(render(old))
        let boundedRep = try XCTUnwrap(render(bounded))
        let evidence = URL(fileURLWithPath: "/private/tmp/valora-artwork-visual-review-20261110")
        try FileManager.default.createDirectory(at: evidence, withIntermediateDirectories: true)
        try oldRep.representation(using: .png, properties: [:])?
            .write(to: evidence.appendingPathComponent("original.png"))
        try boundedRep.representation(using: .png, properties: [:])?
            .write(to: evidence.appendingPathComponent("bounded.png"))
        print("ARTWORK_REVIEW pixels=\(oldRep.pixelsWide)x\(oldRep.pixelsHigh) path=\(evidence.path)")
        let oldPixels = try XCTUnwrap(oldRep.bitmapData)
        let newPixels = try XCTUnwrap(boundedRep.bitmapData)
        XCTAssertEqual(oldRep.pixelsWide, boundedRep.pixelsWide)
        XCTAssertEqual(oldRep.pixelsHigh, boundedRep.pixelsHigh)
        let total = oldRep.pixelsWide * oldRep.pixelsHigh
        var differing = 0
        var sum = 0
        for index in stride(from: 0, to: total * 4, by: 4) {
            let d = abs(Int(oldPixels[index]) - Int(newPixels[index]))
                + abs(Int(oldPixels[index+1]) - Int(newPixels[index+1]))
                + abs(Int(oldPixels[index+2]) - Int(newPixels[index+2]))
            if d > 12 { differing += 1 }
            sum += d
        }
        let ratio = Double(differing) / Double(total)
        print(String(format: "ARTWORK_STAGE differing=%.3f%% meanRGB=%.2f",
                     ratio * 100, Double(sum) / Double(total * 3)))
        // Fine block edges can land differently after the extra downscale;
        // report both the edge-difference ratio and the much lower mean RGB
        // error instead of claiming byte/pixel identity.
        XCTAssertLessThan(ratio, 0.5, "too many visible pixels diverge at 56pt")
        XCTAssertLessThan(Double(sum) / Double(total * 3), 8,
                          "mean RGB error at 56pt is too large")
    }

    func testAlphaAndCorruptDataFallbacks() throws {
        let transparent = try XCTUnwrap(encoded(
            cgImage(width: 300, height: 300, color: .black, alpha: 0), type: .png))
        let opaque = try XCTUnwrap(encoded(
            cgImage(width: 300, height: 300, color: .black, alpha: 1), type: .png))
        let first = ArtworkPalette.extract(try XCTUnwrap(ArtworkImage.prepare(transparent)))
        let second = ArtworkPalette.extract(try XCTUnwrap(ArtworkImage.prepare(opaque)))
        XCTAssertFalse(first.identity.isEmpty)
        XCTAssertNotEqual(first.identity, second.identity,
                          "alpha must participate in the visual identity")
        XCTAssertTrue(ArtworkPalette.extract(nil).colors.isEmpty)

        XCTAssertNil(ArtworkImage.prepare(Data([0, 1, 2, 3])))
        XCTAssertNil(ArtworkImage.prepare(Data()))
    }
}
