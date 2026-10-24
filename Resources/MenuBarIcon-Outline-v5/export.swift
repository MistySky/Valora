import AppKit

// Export resolution variants without changing the generated artwork.
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
guard let source = NSImage(contentsOf: folder.appendingPathComponent("master.png")) else {
    fatalError("Missing master.png")
}
for (filename, pixels) in [("MenuBarIcon.png", 20), ("MenuBarIcon@2x.png", 40),
                           ("MenuBarIcon@3x.png", 60), ("preview-256.png", 256)] {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    source.draw(in: NSRect(x: 0, y: 0, width: pixels, height: pixels),
        from: .zero, operation: .copy, fraction: 1)
    NSGraphicsContext.restoreGraphicsState()
    try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(filename))
}
