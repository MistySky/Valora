import Foundation

/// Text-only geometry from NSMarqueeTextView, 0x100332a70 / 0x100333254.
public struct MarqueeMetrics: Sendable {
    public let overflows: Bool
    public let firstOrigin: Double = 4.5
    public let secondOrigin: Double
    public let firstDestination: Double
    public let secondDestination: Double = 4.5
    public let delay: Double = 1.25
    public let movementDuration: Double
    public let cycleDuration: Double
    public init(textWidth: Double, viewportWidth: Double, longestTextWidth: Double) {
        let width = max(0,textWidth)
        overflows = width + 4.5 > viewportWidth
        secondOrigin = width + 24
        firstDestination = 4.5 - (width + 24)
        movementDuration = width / 30
        cycleDuration = max(width,longestTextWidth) / 30 + 1.25
    }
}
