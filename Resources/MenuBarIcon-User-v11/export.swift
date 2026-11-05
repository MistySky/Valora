import AppKit

// Normalize the supplied template's transparent padding, not its shape.
let input = URL(fileURLWithPath: CommandLine.arguments[1])
let output = URL(fileURLWithPath: CommandLine.arguments[2])
let source = NSBitmapImageRep(data: try Data(contentsOf: input))!
var minX=source.pixelsWide, minY=source.pixelsHigh, maxX=0, maxY=0
for y in 0..<source.pixelsHigh { for x in 0..<source.pixelsWide {
    if source.colorAt(x:x,y:y)!.alphaComponent > 0.02 {
        minX=min(minX,x); minY=min(minY,y); maxX=max(maxX,x); maxY=max(maxY,y)
    }
}}
let crop = source.cgImage!.cropping(to: CGRect(x:minX,y:minY,width:maxX-minX+1,height:maxY-minY+1))!
let image = NSImage(cgImage: crop, size: NSSize(width:crop.width,height:crop.height))
for scale in 1...3 {
    // 22x18pt canvas, with a 20pt-wide mark and original aspect ratio.
    let w=22*scale, h=18*scale
    let rep=NSBitmapImageRep(bitmapDataPlanes:nil,pixelsWide:w,pixelsHigh:h,bitsPerSample:8,
        samplesPerPixel:4,hasAlpha:true,isPlanar:false,colorSpaceName:.deviceRGB,bytesPerRow:0,bitsPerPixel:0)!
    NSGraphicsContext.saveGraphicsState()
    NSGraphicsContext.current=NSGraphicsContext(bitmapImageRep:rep)
    NSGraphicsContext.current?.imageInterpolation = .high
    let inkWidth=CGFloat(20*scale), inkHeight=inkWidth*CGFloat(crop.height)/CGFloat(crop.width)
    image.draw(in: NSRect(x:(CGFloat(w)-inkWidth)/2,y:(CGFloat(h)-inkHeight)/2,width:inkWidth,height:inkHeight),
               from:.zero,operation:.copy,fraction:1)
    NSGraphicsContext.restoreGraphicsState()
    let suffix=scale == 1 ? "" : "@\(scale)x"
    try rep.representation(using:.png,properties:[:])!.write(to:output.appendingPathComponent("MenuBarIcon\(suffix).png"))
}
print("Original ink: \(crop.width)x\(crop.height); normalized: 20x\(20*Double(crop.height)/Double(crop.width))pt")
