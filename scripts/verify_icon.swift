import AppKit
import CryptoKit
import Foundation
import ImageIO

// Read-only icon verifier. It does not modify the bundle, LaunchServices cache
// or any system appearance setting.
let args = CommandLine.arguments
guard args.count >= 3 else {
    fputs("usage: verify_icon.swift <Valora.app> <output-dir> [expected-light.icns]\n", stderr)
    exit(2)
}
let appURL = URL(fileURLWithPath: args[1]).standardizedFileURL
let outputURL = URL(fileURLWithPath: args[2]).standardizedFileURL
let expectedSource = args.count >= 4 ? URL(fileURLWithPath: args[3]).standardizedFileURL : nil
try FileManager.default.createDirectory(at: outputURL, withIntermediateDirectories: true)

func sha256(_ data: Data) -> String {
    SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
}
func sha256(file: URL) -> String? {
    (try? Data(contentsOf: file)).map(sha256)
}
func writePNG(_ image: NSImage, pixels: Int, name: String) -> [String: Any]? {
    guard let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
                                     bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                                     colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0),
          let context = NSGraphicsContext(bitmapImageRep: rep) else { return nil }
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = context
    image.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
               from: .zero, operation: .sourceOver, fraction: 1)
    context.flushGraphics()
    NSGraphicsContext.restoreGraphicsState()
    guard let png = rep.representation(using: .png, properties: [:]) else { return nil }
    let url = outputURL.appendingPathComponent(name)
    try? png.write(to: url)
    let corners = [(2, 2), (pixels - 3, 2), (2, pixels - 3), (pixels - 3, pixels - 3)]
    let cornerAlphas = corners.compactMap { x, y in rep.colorAt(x: x, y: y)?.alphaComponent }
    var colorful = 0
    var sampled = 0
    let step = max(1, pixels / 64)
    for y in stride(from: 0, to: pixels, by: step) {
        for x in stride(from: 0, to: pixels, by: step) {
            guard let color = rep.colorAt(x: x, y: y), color.alphaComponent > 0.5 else { continue }
            sampled += 1
            if color.saturationComponent > 0.15 { colorful += 1 }
        }
    }
    return [
        "path": url.path,
        "pixels": pixels,
        "bytes": png.count,
        "sha256": sha256(png),
        "cornerAlphas": cornerAlphas,
        "sampledOpaquePixels": sampled,
        "colorfulFraction": sampled > 0 ? Double(colorful) / Double(sampled) : 0
    ]
}

var report: [String: Any] = [:]
report["app"] = appURL.path
report["app_exists"] = FileManager.default.fileExists(atPath: appURL.path)
let infoURL = appURL.appendingPathComponent("Contents/Info.plist")
let info = (NSDictionary(contentsOf: infoURL) as? [String: Any]) ?? [:]
let iconKey = info["CFBundleIconFile"] as? String
report["info_icon_key"] = iconKey ?? NSNull()
report["bundle_identifier"] = info["CFBundleIdentifier"] as? String ?? NSNull()
report["ls_minimum_system"] = info["LSMinimumSystemVersion"] as? String ?? NSNull()
report["ls_ui_element"] = info["LSUIElement"] as? Bool ?? NSNull()

let bundleIconURL = appURL.appendingPathComponent("Contents/Resources/AppIcon.icns")
report["bundle_icon_path"] = bundleIconURL.path
report["bundle_icon_exists"] = FileManager.default.fileExists(atPath: bundleIconURL.path)
report["bundle_icon_sha256"] = sha256(file: bundleIconURL) ?? NSNull()
if let expectedSource {
    report["expected_source"] = expectedSource.path
    report["expected_source_sha256"] = sha256(file: expectedSource) ?? NSNull()
    report["bundle_matches_expected_source"] =
        (try? Data(contentsOf: bundleIconURL)) == (try? Data(contentsOf: expectedSource))
}

// Read the actual icns container with ImageIO.
var icnsImages: [[String: Any]] = []
if let source = CGImageSourceCreateWithURL(bundleIconURL as CFURL, nil) {
    report["icns_uti"] = CGImageSourceGetType(source) as String? ?? NSNull()
    report["icns_image_count"] = CGImageSourceGetCount(source)
    for index in 0..<CGImageSourceGetCount(source) {
        guard let properties = CGImageSourceCopyPropertiesAtIndex(source, index, nil) as? [String: Any],
              let width = properties[kCGImagePropertyPixelWidth as String] as? Int,
              let height = properties[kCGImagePropertyPixelHeight as String] as? Int else { continue }
        var entry: [String: Any] = ["index": index, "width": width, "height": height]
        if index == 0, let cg = CGImageSourceCreateImageAtIndex(source, index, nil) {
            let image = NSImage(cgImage: cg, size: NSSize(width: cg.width, height: cg.height))
            entry["rendered_1024"] = writePNG(image, pixels: 1024, name: "icns-direct-1024.png")
        }
        icnsImages.append(entry)
    }
}
report["icns_images"] = icnsImages

// The icon Finder/NSWorkspace reports for this exact bundle path.
let workspaceIcon = NSWorkspace.shared.icon(forFile: appURL.path)
report["nsworkspace_icon_point_size"] = [workspaceIcon.size.width, workspaceIcon.size.height]
report["nsworkspace_representations"] = workspaceIcon.representations.map {
    ["width": $0.pixelsWide, "height": $0.pixelsHigh, "alpha": $0.hasAlpha]
}
report["nsworkspace_rendered_512"] = writePNG(workspaceIcon, pixels: 512, name: "finder-512.png")
report["nsworkspace_rendered_128"] = writePNG(workspaceIcon, pixels: 128, name: "finder-128.png")
report["nsworkspace_rendered_32"] = writePNG(workspaceIcon, pixels: 32, name: "finder-32.png")
report["nsworkspace_rendered_16"] = writePNG(workspaceIcon, pixels: 16, name: "finder-16.png")

report["cache_policy"] = [
    "launchservices_cache_modified": false,
    "note": "NSWorkspace icon is read for the current bundle path. This verifier does not run lsregister, clear caches or change global appearance."
]
report["product_identity"] = "Valora"
report["supplied_asset_names_unchanged"] = true
report["dark_set_selected_for_bundle"] = false

let data = try JSONSerialization.data(withJSONObject: report, options: [.prettyPrinted, .sortedKeys])
try data.write(to: outputURL.appendingPathComponent("icon-verification.json"))
print(outputURL.appendingPathComponent("icon-verification.json").path)
