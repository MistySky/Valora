import AppKit

// Original vector V. Filled swept arms, without a frame or thin wire loops.
// The SVG in this directory is the editable source counterpart.
let folder = URL(fileURLWithPath: CommandLine.arguments[1])
func render(_ pixels: Int, preview: Bool = false) throws {
    let rep = NSBitmapImageRep(bitmapDataPlanes: nil, pixelsWide: pixels, pixelsHigh: pixels,
        bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
        colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current = NSGraphicsContext(bitmapImageRep: rep)
    NSGraphicsContext.current?.shouldAntialias = true
    if preview {
        NSColor(srgbRed: 0.49, green: 0.66, blue: 0.72, alpha: 1).setFill()
        NSBezierPath(rect: NSRect(x: 0, y: 0, width: pixels, height: pixels)).fill()
        NSColor.white.setFill()
    } else { NSColor.black.setFill() }
    let scale = CGFloat(pixels) / 24
    func p(_ x: CGFloat, _ y: CGFloat) -> NSPoint { NSPoint(x: x * scale, y: (24-y) * scale) }
    let path = NSBezierPath()
    path.move(to: p(2.2, 5))
    path.curve(to: p(8.7, 7.9), controlPoint1: p(5.1, 3.7), controlPoint2: p(7.1, 5.4))
    path.line(to: p(12, 13))
    path.line(to: p(17, 5.7))
    path.curve(to: p(22.1, 3.8), controlPoint1: p(18.5, 3.5), controlPoint2: p(20.3, 3.2))
    path.line(to: p(14.7, 15.8))
    path.curve(to: p(9, 16.1), controlPoint1: p(13.1, 18.4), controlPoint2: p(10.8, 18.6))
    path.close()
    path.fill()
    NSGraphicsContext.restoreGraphicsState()
    let name = preview ? "preview-on-menu-blue.png" : (pixels == 20 ? "MenuBarIcon.png" : pixels == 40 ? "MenuBarIcon@2x.png" : pixels == 60 ? "MenuBarIcon@3x.png" : "preview-240.png")
    try rep.representation(using: .png, properties: [:])!.write(to: folder.appendingPathComponent(name))
}
for pixels in [20, 40, 60, 240] { try render(pixels) }
try render(240, preview: true)
