import Foundation

/// 10020534c constructor and NSWaveformView 1003c5e44.
public enum CompactWaveformMetrics: Sendable {
    public static let count=5
    public static let width=2.0
    public static let spacing=1.5
    public static let height=12.0
    public static let duration=0.2
    public static let pauseDuration=0.3
    public static func amplitude(bar:Int,tick:UInt64,seed:UInt64,revision:UInt64,maximumHeight:Int=12)->Double {
        guard bar >= 0 else { return 2 }
        var n=(tick &* 0xbf58476d1ce4e5b9) ^ (UInt64(bar) &* 0x94d049bb133111eb) ^ seed ^ (revision &* 0x9e3779b97f4a7c15)
        n=n &+ 0x9e3779b97f4a7c15
        n=(n ^ (n >> 30)) &* 0xbf58476d1ce4e5b9
        n=(n ^ (n >> 27)) &* 0x94d049bb133111eb
        n=n ^ (n >> 31)
        return Double(n % UInt64(max(2,maximumHeight)-1) + 2)
    }
}

/// Compact constructor 10020534c; expanded constructor 1000dc6e8.
public struct WaveformProfile: Equatable, Sendable {
    public let count:Int
    public let width:Double
    public let spacing:Double
    public let height:Double
    public let side:Double
    public var span:Double { Double(count)*width + Double(count-1)*spacing }
    public static let compact=WaveformProfile(count:5,width:2,spacing:1.5,height:12,side:20)
    public static let expanded=WaveformProfile(count:6,width:2,spacing:2,height:15,side:24)
}

/// 1001fde28 -> 1001f874c: floating artwork subtracts 1.5 from 17.
/// Corner radius from 1001ff210; expanded artwork uses separate metrics.
public enum CompactArtworkMetrics: Sendable {
    public static func side(notch:Bool)->Double { notch ? 20 : 15.5 }
    public static func corner(notch:Bool,elevated:Bool=false)->Double { (notch ? 5 : 4) + (elevated ? 0.5 : 0) }
    // Compatibility for callers that only know the notch/floating branch.
    public static func corner(notch:Bool)->Double { corner(notch:notch,elevated:false) }
    // 1001f874c -> 1001e1e50(7), plus floating-only 1pt.
    public static func leading(notch:Bool)->Double { notch ? 7 : 6.5 }
}
