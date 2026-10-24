import AppKit

/// Display selection is shared by the settings row and status-item submenu.
/// 1.7.9: 0x1003455b0 checks safe area and both auxiliary top regions for the
/// selected display(s). General's tuning section does not use the simulated flag.
enum SettingsDisplayCatalog {
    static var options: [String] {
        var values = ["Main display", "All displays"]
        if NSScreen.screens.contains(where: isBuiltIn) { values.insert("Built-in display", at: 0) }
        return values + NSScreen.screens.map(\.localizedName)
    }
    static func isBuiltIn(_ screen: NSScreen) -> Bool {
        guard let number = screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber else { return false }
        return CGDisplayIsBuiltin(number.uint32Value) != 0
    }
    static func selectedScreens(_ selection: String) -> [NSScreen] {
        switch selection {
        case "All displays": return NSScreen.screens
        case "Built-in display": return NSScreen.screens.filter(isBuiltIn)
        case "Main display": return Array(NSScreen.screens.prefix(1))
        default: return NSScreen.screens.filter { $0.localizedName == selection }
        }
    }
    /// Distinct glyphs for distinct display choices; do not flatten them.
    static func symbol(for selection: String) -> String {
        switch selection {
        case "All displays": return "display.2"
        case "Built-in display": return "laptopcomputer"
        case "Main display": return "desktopcomputer"
        default: return "display"
        }
    }

    static func hasPhysicalNotch(selection: String) -> Bool {
        selectedScreens(selection).contains { screen in
            guard screen.safeAreaInsets.top > 0,
                  let left = screen.auxiliaryTopLeftArea, let right = screen.auxiliaryTopRightArea else { return false }
            return !left.isEmpty && !right.isEmpty
        }
    }
}
