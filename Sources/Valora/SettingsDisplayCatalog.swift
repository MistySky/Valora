import AppKit
import Combine
import ReferenceCore

/// The first render and subsequent screen-change notifications use the same
/// menu snapshot. Mounting a settings page never substitutes a temporary icon.
@MainActor
final class SettingsDisplayMenu: ObservableObject {
    @Published private(set) var choices: [(key: String, title: String)]
    private let forLock: Bool

    init(forLock: Bool, selection: String, displays: [DisplayDescriptor]) {
        self.forLock = forLock
        choices = SettingsDisplayCatalog.menuChoices(for: displays, forLock: forLock, selection: selection)
    }

    func refresh(selection: String, displays: [DisplayDescriptor]) {
        choices = SettingsDisplayCatalog.menuChoices(for: displays, forLock: forLock, selection: selection)
    }

    func displayedSelection(_ value: String) -> String {
        if forLock && value == LockMusicPreferences.automaticDisplay {
            return choices.contains { $0.key == "Built-in display" } ? "Built-in display" : "Main display"
        }
        return value
    }
}

/// Display selection is shared by the settings row and status-item submenu.
/// 1.7.9: 0x1003455b0 checks safe area and both auxiliary top regions for the
/// selected display(s). General's tuning section does not use the simulated flag.
enum SettingsDisplayCatalog {
    static func menuChoices(for displays: [DisplayDescriptor], forLock: Bool, selection: String = "") -> [(key: String, title: String)] {
        let available = displays.filter(\.isActive)
        let groups = Dictionary(grouping: available, by: \.name)
        var modes = [LockDisplayPolicy.mainDisplay, "All displays"]
        if available.contains(where: \.isBuiltIn) { modes.insert("Built-in display", at: 0) }
        var choices = modes.map { ($0, SettingsText.localized($0)) }
        for display in available {
            let group = groups[display.name] ?? []
            let needsID = forLock || group.count > 1
            var title = display.name
            if group.count > 1, let index = group.firstIndex(of: display) {
                title += " (\(index + 1))"
            }
            // Keep a previously chosen UUID checked even after the other
            // same-named display disconnects and this name becomes unique.
            var key = display.name
            if needsID || selection.hasPrefix("display:") {
                let displayKey = LockDisplayPolicy.selectionKey(for: display)
                if needsID || displayKey == selection { key = displayKey }
            }
            choices.append((key, title))
        }
        return choices
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
        default:
            if selection.hasPrefix("display:") {
                return NSScreen.screens.filter { LockDisplayPolicy.selectionKey(for: DisplayDescriptor(screen: $0)) == selection }
            }
            return NSScreen.screens.filter { $0.localizedName == selection }
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
