import AppKit
import SwiftUI

enum SettingsWindowFactory {
    @MainActor static func make<Content: View>(rootView: Content) -> (NSWindow, NSHostingView<Content>) {
        let window = NSWindow(contentRect: NSRect(x: 0, y: 0, width: 620, height: 687),
                              styleMask: [.titled, .closable, .fullSizeContentView], backing: .buffered, defer: false)
        window.title = SettingsPage.general.displayTitle
        window.titleVisibility = .hidden
        window.titlebarAppearsTransparent = true
        window.isReleasedWhenClosed = false
        window.isMovableByWindowBackground = true
        window.tabbingMode = .disallowed
        window.backgroundColor = NSColor(name: nil) { appearance in
            let dark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
            return dark ? NSColor.windowBackgroundColor
                : NSColor(srgbRed: 234/255, green: 234/255, blue: 234/255, alpha: 1)
        }
        let host = NSHostingView(rootView: rootView)
        // The reference dimensions include the title bar. Hosting's inferred
        // minimum size otherwise adds its safe-area height below the fixed UI.
        host.safeAreaRegions = []
        host.sizingOptions = []
        window.contentView = host
        window.setFrame(NSRect(x: 0, y: 0, width: 620, height: 687), display: false)
        // 1.7.9 detail S004: close/minimize/zoom centers are 25.75/48.75/71.75 pt
        // from the window top with a 14-15 pt visible circle (evidence/original/
        // general-top.png, 2x capture). The standard controls render a fixed
        // 12.5 pt circle, so they stay hidden for window behavior and the visible
        // circles come from TrafficLightsView.
        let container = NSView(frame: NSRect(x: 0, y: 0, width: 620, height: 687))
        host.frame = container.bounds
        host.autoresizingMask = [.width, .height]
        container.addSubview(host)
        window.contentView = container
        // Install above the titlebar so the visible circles are neither covered
        // by nor competing with the hidden standard buttons.
        let lights = TrafficLightsView(window: window)
        container.superview?.addSubview(lights)
        for type in [NSWindow.ButtonType.closeButton, .miniaturizeButton, .zoomButton] {
            window.standardWindowButton(type)?.isHidden = true
        }
        return (window, host)
    }
}
