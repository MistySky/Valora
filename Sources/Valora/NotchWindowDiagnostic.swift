import AppKit
import Foundation
import SwiftUI

/// Pure budget/dedup policy for the default-off own-window diagnostic. Normal
/// state changes may fill only a small prefix; the remainder is reserved for
/// lock/session transitions so ordinary idle refresh cannot exhaust the log
/// before the user locks the screen.
struct NotchDiagnosticPolicy {
    let totalLimit: Int
    let normalLimit: Int
    let lockLimit: Int
    private(set) var totalCount = 0
    private(set) var normalCount = 0
    private(set) var lockCount = 0
    private var lastKey: String?

    init(totalLimit: Int = 120, normalLimit: Int = 24, lockLimit: Int = 96) {
        self.totalLimit = max(0, totalLimit)
        self.normalLimit = max(0, normalLimit)
        self.lockLimit = max(0, lockLimit)
    }

    mutating func shouldRecord(key: String, locked: Bool) -> Bool {
        guard key != lastKey, totalCount < totalLimit else { return false }
        if locked {
            guard lockCount < lockLimit else { return false }
            lockCount += 1
        } else {
            guard normalCount < normalLimit else { return false }
            normalCount += 1
        }
        totalCount += 1
        lastKey = key
        return true
    }
}

/// Each phase owns separate lanes. Animation frame traffic can never consume
/// window, Space or system-event slots, nor any later unlock-phase slots.
struct NotchDiagnosticCapturePolicy {
    private(set) var totalCount = 0
    private var counts: [String: Int] = [:]
    private var lastKeys: [String: String] = [:]
    private var lastTimes: [String: TimeInterval] = [:]
    let totalLimit = 120

    mutating func shouldRecord(kind: String, phase: String, key: String,
                               now: TimeInterval) -> Bool {
        let lane = phase + "|" + kind
        let limit: Int
        let interval: TimeInterval
        switch kind {
        // Per-phase lanes are intentionally small so a complete
        // locking→neutralizing→locked→unlocking→restoring→returned-to-desktop
        // lifecycle can never consume the final primary handoff/event slots.
        case "swiftui-layout": limit = 3; interval = 0.12
        case "window": limit = 4; interval = 0.08
        case "space": limit = 3; interval = 0
        case "event": limit = 2; interval = 0
        case "overlay": limit = 4; interval = 0.08
        default: return false
        }
        guard totalCount < totalLimit, counts[lane, default: 0] < limit,
              lastKeys[lane] != key else { return false }
        if let time = lastTimes[lane], now - time < interval { return false }
        totalCount += 1
        counts[lane, default: 0] += 1
        lastKeys[lane] = key
        lastTimes[lane] = now
        return true
    }
}

/// Pure coordinate decisions used by the diagnostic; kept separate so flipped
/// hosting/view coordinates and negative screen origins can be tested without
/// constructing an NSWindow.
enum NotchDiagnosticCoordinate {
    /// AppKit flipped views use minY as the top edge; non-flipped use maxY.
    static func hostTop(bounds: CGRect, isFlipped: Bool) -> CGFloat {
        isFlipped ? bounds.minY : bounds.maxY
    }

    /// A logical window->screen point for diagnostics only. The live recorder
    /// uses NSView/NSWindow conversion; this helper makes the coordinate contract
    /// explicit and testable for negative-origin screens.
    static func logicalScreenPoint(windowPoint: CGPoint, screenOrigin: CGPoint) -> CGPoint {
        CGPoint(x: screenOrigin.x + windowPoint.x, y: screenOrigin.y + windowPoint.y)
    }
}

/// Default-off, bounded, own-window geometry probe for a single user-assisted
/// run. It records only Valora's own screen/panel/content values; it never
/// enumerates other applications, reads titles, or starts a repeating timer.
@MainActor
final class NotchWindowDiagnostic {
    static let shared = NotchWindowDiagnostic()
    private let path: String?
    private var policy = NotchDiagnosticCapturePolicy()
    private var observedSystemLock = false

    private func capturePhase(_ phase: String) -> String {
        phase == "hidden" && observedSystemLock ? "returned-to-desktop" : phase
    }

    private init() {
        path = ProcessInfo.processInfo.environment["VALORA_NOTCH_DIAGNOSTIC"]
    }

    var isEnabled: Bool { path != nil }

    func record(role: String = "primary",
                reason: String,
                phase: String,
                displayID: String,
                screenFrame: CGRect,
                safeAreaTop: CGFloat,
                menuBarHeight: CGFloat,
                auxLeftWidth: CGFloat?,
                auxRightWidth: CGFloat?,
                forceSimulated: Bool,
                hasPhysicalNotch: Bool,
                compact: CGSize,
                visibleSize: CGSize,
                contourTopInset: CGFloat,
                panelBefore: CGRect,
                panelAfter: CGRect,
                hostFrame: CGRect,
                hostBounds: CGRect,
                hostSafeArea: NSEdgeInsets,
                hostTop: CGFloat,
                contentTopScreen: CGPoint?,
                visible: Bool,
                sessionLocked: Bool,
                notchMounted: Bool,
                windowNumber: Int) {
        guard let path else { return }
        var key = reason + "|" + phase + "|" + displayID
        key += "|" + String(describing: screenFrame)
        key += "|" + String(Double(safeAreaTop)) + "|" + String(Double(menuBarHeight))
        key += "|" + String(describing: auxLeftWidth) + "|" + String(describing: auxRightWidth)
        key += "|" + String(forceSimulated) + "|" + String(hasPhysicalNotch)
        key += "|" + String(describing: compact) + "|" + String(describing: visibleSize)
        key += "|" + String(Double(contourTopInset)) + "|" + String(describing: panelBefore)
        key += "|" + String(describing: panelAfter) + "|" + String(describing: hostFrame)
        key += "|" + String(describing: hostBounds) + "|" + String(describing: hostSafeArea)
        key += "|" + String(Double(hostTop)) + "|" + String(describing: contentTopScreen)
        key += "|" + String(visible) + "|" + String(sessionLocked)
        key += "|" + String(notchMounted) + "|" + String(windowNumber) + "|" + role
        guard policy.shouldRecord(kind: "window", phase: capturePhase(phase), key: key,
                                  now: ProcessInfo.processInfo.systemUptime) else { return }
        write([
            "kind": "window",
            "role": role,
            "sequence": policy.totalCount,
            "time": Date().timeIntervalSince1970,
            "reason": reason,
            "phase": phase,
            "display": displayID,
            "screen": Self.rect(screenFrame),
            "safeAreaTop": safeAreaTop,
            "menuBarHeight": menuBarHeight,
            "auxLeftWidth": auxLeftWidth as Any,
            "auxRightWidth": auxRightWidth as Any,
            "forceSimulated": forceSimulated,
            "hasPhysicalNotch": hasPhysicalNotch,
            "compact": Self.size(compact),
            "visibleSize": Self.size(visibleSize),
            "contourTopInset": contourTopInset,
            "panelBefore": Self.rect(panelBefore),
            "panelAfter": Self.rect(panelAfter),
            "hostFrame": Self.rect(hostFrame),
            "hostBounds": Self.rect(hostBounds),
            "hostSafeArea": [hostSafeArea.top, hostSafeArea.left, hostSafeArea.bottom, hostSafeArea.right],
            "hostTop": hostTop,
            "contentTopScreen": contentTopScreen.map { [$0.x, $0.y] } as Any,
            "visible": visible,
            "sessionLocked": sessionLocked,
            "notchMounted": notchMounted,
            "windowNumber": windowNumber,
            "serverBoundsQuartz": ownServerBounds(windowNumber)
        ])
    }

    /// Actual SwiftUI notch-region probe. The rect is SwiftUI global logical
    /// coordinates, not yet WindowServer pixels; named separately from host and
    /// screen coordinates so it cannot be mistaken for a rendered frame.
    func recordSwiftUILayout(phase: String, globalRect: CGRect) {
        guard let path else { return }
        var key = "swiftui-layout|" + phase
        key += "|" + String(describing: globalRect)
        guard policy.shouldRecord(kind: "swiftui-layout", phase: capturePhase(phase), key: key,
                                  now: ProcessInfo.processInfo.systemUptime) else { return }
        write(["kind": "swiftui-layout", "sequence": policy.totalCount,
               "time": Date().timeIntervalSince1970, "phase": phase,
               "source": "NotchView.shape", "globalRect": Self.rect(globalRect)])
    }

    /// Dedicated overlay/role record. It reports only Valora's own window
    /// number and its Quartz bounds (never other windows or contents).
    func recordOverlay(reason: String, phase: String, frame: CGRect,
                       hostFrame: CGRect, visible: Bool, sessionLocked: Bool,
                       windowNumber: Int, space: [String: Any]) {
        guard let path else { return }
        let locked = sessionLocked || phase != "hidden"
        var key = "overlay|" + reason + "|" + phase + "|" + String(describing: frame)
        key += "|" + String(describing: hostFrame) + "|" + String(visible)
        key += "|" + String(windowNumber) + "|" + String(describing: space)
        guard policy.shouldRecord(kind: "overlay", phase: capturePhase(phase), key: key,
                                  now: ProcessInfo.processInfo.systemUptime) else { return }
        write(["kind": "overlay", "role": "lock-overlay", "sequence": policy.totalCount,
               "time": Date().timeIntervalSince1970, "reason": reason, "phase": phase,
               "frame": Self.rect(frame), "hostFrame": Self.rect(hostFrame),
               "visible": visible,
               "windowNumber": windowNumber, "quartzBounds": Self.quartzBounds(windowNumber) as Any,
               "space": space])
    }

    private static func quartzBounds(_ windowNumber: Int) -> [CGFloat]? {
        guard windowNumber > 0,
              let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(windowNumber)) as? [[String: Any]],
              let dictionary = list.first?[kCGWindowBounds as String] as? [String: Any],
              let rect = CGRect(dictionaryRepresentation: dictionary as CFDictionary) else { return nil }
        return [rect.minX, rect.minY, rect.width, rect.height]
    }

    /// One-shot runtime guard for the isolated lock surface: a window that is
    /// owned by a private Space can be moved out of the composited user session,
    /// and a silently invisible lock surface is worse than the known-visible
    /// fallback. Returns nil when the window list is unavailable so callers only
    /// act on a definite answer. Uses only this process's own window number.
    static func isWindowComposited(_ windowNumber: Int) -> Bool? {
        guard windowNumber > 0,
              let list = CGWindowListCopyWindowInfo([.optionIncludingWindow], CGWindowID(windowNumber)) as? [[String: Any]],
              let entry = list.first else { return nil }
        return (entry[kCGWindowIsOnscreen as String] as? Bool) ?? false
    }

    /// Space membership is recorded by the lock coordinator, which owns the
    /// presentation Space; these are scalar snapshots only, never other apps.
    func recordSpace(reason: String, phase: String, sessionLocked: Bool,
                     windowNumber: Int, before: [String: Any], after: [String: Any]) {
        guard let path else { return }
        let key = ["space", reason, phase, String(windowNumber),
                   String(describing: before), String(describing: after)].joined(separator: "|")
        guard policy.shouldRecord(kind: "space", phase: capturePhase(phase), key: key,
                                  now: ProcessInfo.processInfo.systemUptime) else { return }
        write(["kind": "space", "sequence": policy.totalCount,
               "time": Date().timeIntervalSince1970, "reason": reason, "phase": phase,
               "windowNumber": windowNumber, "before": before, "after": after])
    }

    func recordSystemEvent(locked: Bool, phase: String) {
        guard isEnabled else { return }
        if locked { observedSystemLock = true }
        let edge = locked ? "lock-request" : "unlock-request"
        guard policy.shouldRecord(kind: "event", phase: edge, key: phase,
                                  now: ProcessInfo.processInfo.systemUptime) else { return }
        write(["kind": "event", "sequence": policy.totalCount,
               "time": Date().timeIntervalSince1970, "edge": edge,
               "previousPhase": phase, "phase": edge])
    }

    /// Query exactly our window ID and retain bounds only. Quartz coordinates
    /// are named separately; this API may still omit compositor-only transforms.
    private func ownServerBounds(_ number: Int) -> Any {
        guard number > 0,
              let rows = CGWindowListCopyWindowInfo(.optionIncludingWindow,
                  CGWindowID(number)) as? [[String: Any]],
              let row = rows.first(where: {
                  ($0[kCGWindowNumber as String] as? NSNumber)?.intValue == number
              }), let bounds = row[kCGWindowBounds as String] as? [String: Any]
        else { return "unknown" }
        return bounds
    }

    private func write(_ record: [String: Any]) {
        guard let path,
              let data = try? JSONSerialization.data(withJSONObject: record, options: [.sortedKeys]) else { return }
        let url = URL(fileURLWithPath: path)
        try? FileManager.default.createDirectory(at: url.deletingLastPathComponent(),
                                                 withIntermediateDirectories: true)
        if FileManager.default.fileExists(atPath: path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                try? handle.seekToEnd()
                try? handle.write(contentsOf: data + Data([0x0A]))
                try? handle.close()
            }
        } else {
            try? (data + Data([0x0A])).write(to: url, options: .atomic)
        }
    }

    private static func rect(_ value: CGRect) -> [CGFloat] {
        [value.minX, value.minY, value.width, value.height]
    }
    private static func size(_ value: CGSize) -> [CGFloat] { [value.width, value.height] }
}


/// Diagnostic-only SwiftUI probe. It is inserted into the actual NotchView
/// shape only while the default-off diagnostic is enabled. `global` here is
/// SwiftUI logical global space, not a WindowServer pixel/screen claim.
struct NotchLayoutProbe: View {
    let phase: String
    var body: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { report(proxy.frame(in: .global)) }
                .onChange(of: proxy.frame(in: .global)) { _, rect in report(rect) }
                .onChange(of: phase) { _, _ in report(proxy.frame(in: .global)) }
        }
    }

    private func report(_ rect: CGRect) {
        NotchWindowDiagnostic.shared.recordSwiftUILayout(
            phase: phase, globalRect: rect)
    }
}
