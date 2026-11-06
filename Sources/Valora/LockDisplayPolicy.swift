import AppKit
import ReferenceCore

/// Lock surfaces follow available hardware, independently of music targets.
/// NSScreen order supplies the main-display fallback; inactive/offline built-in
/// displays (including clamshell mode) are not eligible.
enum LockDisplayPolicy {
    static func select(from displays: [DisplayDescriptor]) -> DisplayDescriptor? {
        let available = displays.filter(\.isActive)
        return available.first(where: \.isBuiltIn) ?? available.first
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
