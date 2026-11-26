import AppKit
import ColorSync
import ReferenceCore

/// Lock surfaces follow available hardware, independently of music targets.
/// NSScreen order supplies the main-display fallback; inactive/offline built-in
/// displays (including clamshell mode) are not eligible.
enum LockDisplayPolicy {
    static let mainDisplay = "Main display"

    /// Store the hardware UUID independently of its name and current arrangement.
    static func selectionKey(for display: DisplayDescriptor) -> String {
        if let id = UInt32(display.id),
           let uuid = CGDisplayCreateUUIDFromDisplayID(id)?.takeRetainedValue() {
            return "display:" + (CFUUIDCreateString(nil, uuid) as String)
        }
        return "display:" + display.id
    }

    static func select(from displays: [DisplayDescriptor],
                       preference: String = LockMusicPreferences.automaticDisplay) -> DisplayDescriptor? {
        let available = displays.filter(\.isActive)
        if preference == mainDisplay || preference == "All displays" { return available.first }
        if preference.hasPrefix("display:"),
           let chosen = available.first(where: { selectionKey(for: $0) == preference }) {
            return chosen
        }
        return available.first(where: \.isBuiltIn) ?? available.first
    }

    static func targets(from displays: [DisplayDescriptor], preference: String) -> [DisplayDescriptor] {
        if preference == "All displays" { return displays.filter(\.isActive) }
        return select(from: displays, preference: preference).map { [$0] } ?? []
    }

    static func availableDisplays() -> [DisplayDescriptor] {
        NSScreen.screens.map(DisplayDescriptor.init(screen:))
    }

    /// Lock selection stays independent of the music display choice, but the
    /// *shape* follows the existing "force simulated notch" switch on screens
    /// that have no physical notch (user decision 2026-11-05). A real notch
    /// keeps its hardware geometry regardless of the switch.
    static func geometry(for display: DisplayDescriptor, simulated: Bool = false) -> NotchGeometry {
        let hasPhysicalNotch = display.safeAreaTop > 0
        return .calculate(screenWidth: display.frame.width, safeAreaTop: display.safeAreaTop,
                          auxiliaryLeftWidth: display.auxiliaryLeftWidth,
                          auxiliaryRightWidth: display.auxiliaryRightWidth,
                          menuBarHeight: display.menuBarHeight,
                          simulated: simulated && !hasPhysicalNotch)
    }
}
