import AppKit
import SwiftUI

/// Opt-in synthetic two-display check. Uses the real WindowCoordinator with
/// injected display frames (including a negative external origin), real panels
/// and real NotchView hierarchy; it does not touch production preferences or
/// media.
enum MultiDisplayVerification {
    @MainActor static func run(model: AppModel, coordinator: WindowCoordinator, output: String) {
        Task { @MainActor in
            let directory = URL(fileURLWithPath: output, isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var checks: [[String: Any]] = []
            @MainActor func check(_ name: String, _ passed: Bool) {
                checks.append(["name": name, "passed": passed])
            }
            func settle(_ seconds: Double = 0.65) async {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
            @MainActor func capture(_ name: String, view: NSView?) throws {
                guard let view else { return }
                view.layoutSubtreeIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
                try png.write(to: directory.appendingPathComponent(name + ".png"))
            }

            let ids = coordinator.verificationScreenIDs
            check("injected all-displays creates two panels", ids == ["builtin", "external"])
            check("secondary count excludes active panel", coordinator.verificationSecondaryPanels.count == 1)
            let first = ids.first ?? ""
            let second = ids.dropFirst().first ?? ""
            check("built-in starts active", coordinator.verificationActiveScreenID == first)

            coordinator.verificationActivateScreen(second)
            await settle(0.2)
            check("external panel becomes active", coordinator.verificationActiveScreenID == second)
            coordinator.expand()
            await settle(1.0)
            check("active external pill expands", model.expanded)
            try? capture("active-external-expanded", view: coordinator.panel.contentView)
            check("passive built-in remains the only secondary", coordinator.verificationSecondaryPanels.count == 1)
            try? capture("passive-built-in-compact", view: coordinator.verificationSecondaryPanels.first?.view)

            coordinator.verificationSetPointer(screenID: second, inside: false)
            coordinator.verificationActivateScreen(first)
            await settle(0.6)
            check("switching active collapses the previous panel", !model.expanded)
            check("first screen becomes active", coordinator.verificationActiveScreenID == first)
            try? capture("active-built-in-compact", view: coordinator.panel.contentView)

            coordinator.verificationSetPointer(screenID: second, inside: true)
            model.presenter.cancelPeek(reset: true)
            coordinator.verificationTrackChanged(identity: "first")
            coordinator.verificationTrackChanged(identity: "second")
            await settle(0.2)
            check("track change previews on the pointer target screen",
                  coordinator.verificationActiveScreenID == second && model.songPeek.visible)
            check("passive panel content remains shared and compact",
                  coordinator.verificationSecondaryPanels.count == 1 && model.title.contains("多屏"))
            try? capture("peek-on-external", view: coordinator.panel.contentView)

            let external = DisplayDescriptor(id: "external", name: "External display",
                frame: CGRect(x: -1920, y: -200, width: 1920, height: 1080), safeAreaTop: 0,
                auxiliaryLeftWidth: nil, auxiliaryRightWidth: nil, menuBarHeight: 24)
            let frame = CGRect(x: external.frame.midX - 312, y: external.frame.maxY - 320, width: 624, height: 320)
            check("negative-origin external hit test accepts its contour",
                  coordinator.verificationContains(screenID: second, point: CGPoint(x: frame.midX, y: frame.maxY - 10)))
            check("negative-origin external transparent area passes through",
                  !coordinator.verificationContains(screenID: second, point: CGPoint(x: frame.midX + 500, y: frame.maxY - 10)))

            let result: [String: Any] = ["passed": checks.allSatisfy { $0["passed"] as? Bool == true }, "checks": checks]
            if let data = try? JSONSerialization.data(withJSONObject: result, options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: directory.appendingPathComponent("verification.json"))
            }
            UserDefaults(suiteName: AppRuntimeDefaults.qaSuiteName)?.removeObject(forKey: "referenceSettingsUI")
            NSApp.terminate(nil)
        }
    }
}
