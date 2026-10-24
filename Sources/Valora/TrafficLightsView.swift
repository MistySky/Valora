import AppKit

/// 1.7.9 detail S004: the reference window draws 15 pt traffic-light circles at
/// 25.75 / 48.75 / 71.75 pt from the window top-left. AppKit's standard buttons
/// render a fixed 12.5 pt circle regardless of their frame, so the visible
/// circles are drawn here. The standard buttons stay hidden in the hierarchy so
/// window behavior (Cmd+W, accessibility of the window) is unchanged.
final class TrafficLightsView: NSView {
    private weak var hostedWindow: NSWindow?
    private let centersX: [CGFloat] = [25.75, 48.75, 71.75]
    private let centerYFromTop: CGFloat = 25.75
    private let diameter: CGFloat = 15
    private var buttons: [NSButton] = []
    private var keyObservers: [NSObjectProtocol] = []

    init(window: NSWindow) {
        self.hostedWindow = window
        super.init(frame: NSRect(x: 0, y: window.frame.height - 53,
                                 width: 200, height: 53))
        autoresizingMask = [.minYMargin]
        for (index, centerX) in centersX.enumerated() {
            let button = NSButton(frame: NSRect(x: centerX - diameter / 2,
                                                y: bounds.height - centerYFromTop - diameter / 2,
                                                width: diameter, height: diameter))
            button.isBordered = false
            button.wantsLayer = true
            button.layer?.cornerRadius = diameter / 2
            button.layer?.borderWidth = 1
            button.title = ""
            button.identifier = NSUserInterfaceItemIdentifier(["trafficLight.close", "trafficLight.minimize", "trafficLight.zoom"][index])
            button.setAccessibilityLabel(["关闭窗口", "最小化", "缩放"][index])
            if index == 0 {
                button.target = self
                button.action = #selector(closeWindow)
                button.isEnabled = true
            } else {
                // The settings window is neither miniaturizable nor resizable.
                button.isEnabled = false
            }
            addSubview(button)
            buttons.append(button)
        }
        for name in [NSWindow.didBecomeKeyNotification, NSWindow.didResignKeyNotification] {
            keyObservers.append(NotificationCenter.default.addObserver(forName: name, object: window, queue: .main) { [weak self] _ in
                MainActor.assumeIsolated { self?.updateAppearance() }
            })
        }
        updateAppearance()
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    isolated deinit {
        keyObservers.forEach(NotificationCenter.default.removeObserver)
    }

    private func updateAppearance() {
        let key = hostedWindow?.isKeyWindow ?? false
        let closeFill = key ? NSColor(srgbRed: 245/255, green: 112/255, blue: 107/255, alpha: 1)
                            : NSColor(srgbRed: 220/255, green: 221/255, blue: 225/255, alpha: 1)
        let closeBorder = key ? NSColor(srgbRed: 231/255, green: 76/255, blue: 84/255, alpha: 1)
                              : NSColor(srgbRed: 196/255, green: 197/255, blue: 199/255, alpha: 1)
        let grayFill = NSColor(srgbRed: 220/255, green: 221/255, blue: 225/255, alpha: 1)
        let grayBorder = NSColor(srgbRed: 196/255, green: 197/255, blue: 199/255, alpha: 1)
        for (index, button) in buttons.enumerated() {
            button.layer?.backgroundColor = (index == 0 ? closeFill : grayFill).cgColor
            button.layer?.borderColor = (index == 0 ? closeBorder : grayBorder).cgColor
        }
    }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Only the circles participate; the rest of the title area keeps dragging
        // the window through the background.
        let local = convert(point, from: superview)
        for button in buttons where button.frame.insetBy(dx: -2, dy: -2).contains(local) {
            return button
        }
        return nil
    }

    @objc private func closeWindow() {
        hostedWindow?.performClose(nil)
    }
}
