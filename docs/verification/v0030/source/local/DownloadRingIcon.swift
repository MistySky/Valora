// Ring/arrow menu-bar drawing derived from Convoy's download status
// presentation. The source app used a stock arrow.down.circle icon; this
// project needs the real merged-progress ring, so the shape is drawn locally
// while the row/segment visuals remain the migrated views.
import AppKit
import Foundation

enum DownloadRingKind: Equatable, Sendable {
    case idle
    case active(progress: Double?)
    case paused(progress: Double?)
    case failed
}

struct DownloadRingDescriptor: Equatable, Sendable {
    let kind: DownloadRingKind
    var phase: Double = 0

    static func make(items: [DownloadItemSnapshot], phase: Double) -> DownloadRingDescriptor {
        let active: Set<DownloadItemState> = [.waiting, .starting, .validating, .refreshingLink, .downloading]
        let running = items.filter { active.contains($0.state) }
        if !running.isEmpty {
            if running.contains(where: { $0.hasUnknownTotalSize || $0.isMerging }) {
                return DownloadRingDescriptor(kind: .active(progress: nil), phase: phase)
            }
            let total = running.reduce(Int64(0)) { $0 + max(0, $1.totalBytes) }
            let done = running.reduce(Int64(0)) { $0 + max(0, $1.downloadedBytes) }
            let progress = total > 0 ? min(1, max(0, Double(done) / Double(total))) : nil
            return DownloadRingDescriptor(kind: .active(progress: progress), phase: phase)
        }
        if let paused = items.filter({ $0.state == .paused }).max(by: { $0.createdAt < $1.createdAt }) {
            let progress = paused.totalBytes > 0
                ? min(1, max(0, Double(paused.downloadedBytes) / Double(paused.totalBytes)))
                : nil
            return DownloadRingDescriptor(kind: .paused(progress: progress), phase: phase)
        }
        if !items.isEmpty, items.allSatisfy({ $0.state == .failed }) {
            return DownloadRingDescriptor(kind: .failed)
        }
        return DownloadRingDescriptor(kind: .idle)
    }
}

enum DownloadRingIcon {
    static let size = NSSize(width: 18, height: 18)

    /// A template image so macOS handles the menu-bar appearance. No image
    /// cache: one current image is enough, and the timer stops when idle.
    static func image(for descriptor: DownloadRingDescriptor) -> NSImage {
        let image = NSImage(size: size)
        image.lockFocus()
        defer { image.unlockFocus() }
        NSColor.black.setStroke()
        NSColor.black.setFill()

        let rect = NSRect(x: 1.5, y: 1.5, width: size.width - 3, height: size.height - 3)
        let track = NSBezierPath(ovalIn: rect)
        track.lineWidth = 1.5
        NSColor.black.withAlphaComponent(0.30).setStroke()
        track.stroke()

        switch descriptor.kind {
        case .active(nil):
            let start = descriptor.phase.truncatingRemainder(dividingBy: 1) * 360
            let arc = NSBezierPath()
            arc.appendArc(withCenter: NSPoint(x: size.width / 2, y: size.height / 2),
                          radius: rect.width / 2, startAngle: start, endAngle: start + 105, clockwise: false)
            arc.lineWidth = 1.8
            NSColor.black.setStroke()
            arc.stroke()
        case .active(let progress?), .paused(let progress?):
            let arc = NSBezierPath()
            arc.appendArc(withCenter: NSPoint(x: size.width / 2, y: size.height / 2),
                          radius: rect.width / 2, startAngle: 90,
                          endAngle: 90 - max(0, min(1, progress)) * 360, clockwise: true)
            arc.lineWidth = 1.8
            NSColor.black.setStroke()
            arc.stroke()
        case .active(nil), .paused(nil):
            break
        case .idle, .active(_), .paused(_), .failed:
            break
        }

        if case .failed = descriptor.kind {
            let exclamation = NSBezierPath()
            exclamation.move(to: NSPoint(x: size.width / 2, y: 11.5))
            exclamation.line(to: NSPoint(x: size.width / 2, y: 6.2))
            exclamation.lineWidth = 1.8
            exclamation.lineCapStyle = .round
            exclamation.stroke()
            let dot = NSRect(x: size.width / 2 - 0.9, y: 3.8, width: 1.8, height: 1.8)
            NSBezierPath(ovalIn: dot).fill()
        } else {
            // Down arrow in the center, matching Convoy's download symbol.
            let arrow = NSBezierPath()
            arrow.move(to: NSPoint(x: size.width / 2, y: 11.7))
            arrow.line(to: NSPoint(x: size.width / 2, y: 5.6))
            arrow.lineWidth = 1.7
            arrow.lineCapStyle = .round
            arrow.stroke()
            let head = NSBezierPath()
            head.move(to: NSPoint(x: 5.7, y: 8.1))
            head.line(to: NSPoint(x: size.width / 2, y: 5.2))
            head.line(to: NSPoint(x: 12.3, y: 8.1))
            head.lineWidth = 1.7
            head.lineCapStyle = .round
            head.lineJoinStyle = .round
            head.stroke()
        }
        image.isTemplate = true
        return image
    }
}
