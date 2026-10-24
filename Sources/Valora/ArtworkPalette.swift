import AppKit
import CryptoKit

/// Bounded local palette extraction. The original's dominant-color selection
/// algorithm is not yet reproduced; its progress style and white-filter rule are.
enum ArtworkPalette {
    static func extract(_ image: NSImage?) -> (identity: String, colors: [NSColor]) {
        guard let image, let data = image.tiffRepresentation else { return ("",[]) }
        let identity = SHA256.hash(data:data).map { String(format:"%02x",$0) }.joined()
        var bounds = CGRect(origin:.zero,size:image.size)
        guard let cg = image.cgImage(forProposedRect:&bounds,context:nil,hints:nil) else { return (identity,[]) }
        let size = 32
        var pixels = [UInt8](repeating:0,count:size*size*4)
        let rendered = pixels.withUnsafeMutableBytes { bytes -> Bool in
            guard let context = CGContext(data:bytes.baseAddress,width:size,height:size,bitsPerComponent:8,bytesPerRow:size*4,
                space:CGColorSpace(name:CGColorSpace.sRGB)!,bitmapInfo:CGImageAlphaInfo.premultipliedLast.rawValue) else { return false }
            context.interpolationQuality = .medium
            context.draw(cg,in:CGRect(x:0,y:0,width:size,height:size)); return true
        }
        guard rendered else { return (identity,[]) }
        var buckets: [Int:(count:Int,r:Double,g:Double,b:Double)] = [:]
        for index in stride(from:0,to:pixels.count,by:4) {
            let alpha = Double(pixels[index+3])/255
            guard alpha > 0.5 else { continue }
            let r = min(1,Double(pixels[index])/255/alpha), g = min(1,Double(pixels[index+1])/255/alpha), b = min(1,Double(pixels[index+2])/255/alpha)
            let key = Int(r*7)*64 + Int(g*7)*8 + Int(b*7)
            let old = buckets[key] ?? (0,0,0,0)
            buckets[key] = (old.count+1,old.r+r,old.g+g,old.b+b)
        }
        let sorted = buckets.sorted { $0.value.count == $1.value.count ? $0.key < $1.key : $0.value.count > $1.value.count }
        var selected: [NSColor] = []
        for (_,bucket) in sorted {
            let n = Double(bucket.count), r = bucket.r/n, g = bucket.g/n, b = bucket.b/n
            if selected.contains(where: { pow($0.redComponent-r,2)+pow($0.greenComponent-g,2)+pow($0.blueComponent-b,2) < 0.08 }) { continue }
            selected.append(NSColor(srgbRed:r,green:g,blue:b,alpha:1))
            if selected.count == 4 { break }
        }
        return (identity,selected)
    }
    static func luminance(_ color: NSColor) -> Double {
        func linear(_ value:Double) -> Double { value <= 0.03928 ? value/12.92 : pow((value+0.055)/1.055,2.4) }
        return 0.2126*linear(color.redComponent)+0.7152*linear(color.greenComponent)+0.0722*linear(color.blueComponent)
    }
}
