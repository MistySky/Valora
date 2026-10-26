import AppKit
import SwiftUI
import ReferenceCore

actor EmptyConnectivitySource: ConnectedAudioSource {
    func snapshot() async -> ConnectedAudioSnapshot {
        ConnectedAudioSnapshot(devices: [], output: "")
    }
}

@MainActor
final class ConnectivitySoundSpy: LowBatterySoundPlaying {
    private(set) var plays = 0
    private(set) var stops = 0
    func playLowBattery() { plays += 1 }
    func stopLowBattery() { stops += 1 }
}

/// Synthetic connection/battery rendering and controller checks. It uses an
/// empty source and a sound spy, so no Bluetooth query, sound, player or system
/// setting is touched.
enum ConnectivityVerification {
    @MainActor static func run(model: AppModel, coordinator: WindowCoordinator,
                               controller: ConnectivityController,
                               sound: ConnectivitySoundSpy, output: String) {
        Task { @MainActor in
            let directory = URL(fileURLWithPath: output, isDirectory: true)
            try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            var checks: [[String: Any]] = []
            @MainActor func check(_ name: String, _ passed: Bool) {
                checks.append(["name": name, "passed": passed])
            }
            func settle(_ seconds: Double = 0.35) async {
                try? await Task.sleep(nanoseconds: UInt64(seconds * 1_000_000_000))
            }
            @MainActor func capture(_ name: String, view: NSView? = nil) throws {
                guard let view = view ?? coordinator.panel.contentView else { return }
                view.layoutSubtreeIfNeeded()
                guard let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds) else { return }
                view.cacheDisplay(in: view.bounds, to: bitmap)
                guard let png = bitmap.representation(using: .png, properties: [:]) else { return }
                try png.write(to: directory.appendingPathComponent(name + ".png"))
                let canvas = NSImage(size: view.bounds.size)
                canvas.lockFocus()
                NSColor(calibratedWhite: 0.94, alpha: 1).setFill()
                NSBezierPath(rect: view.bounds).fill()
                let captured = NSImage(size: view.bounds.size)
                captured.addRepresentation(bitmap)
                captured.draw(in: view.bounds)
                canvas.unlockFocus()
                if let tiff = canvas.tiffRepresentation,
                   let composite = NSBitmapImageRep(data: tiff)?.representation(using: .png, properties: [:]) {
                    try composite.write(to: directory.appendingPathComponent(name + "-review.png"))
                }
            }
            @MainActor func snapshot(_ devices: [AudioDevice]) -> ConnectedAudioSnapshot {
                ConnectedAudioSnapshot(devices: devices, output: devices.first?.name ?? "")
            }
            let usage = Bundle.main.object(forInfoDictionaryKey: "NSBluetoothAlwaysUsageDescription") as? String
            check("Bluetooth always-usage description is packaged", !(usage ?? "").isEmpty)
            let calendarUsage = Bundle.main.object(forInfoDictionaryKey: "NSCalendarsFullAccessUsageDescription") as? String
            check("Calendar full-access usage description is packaged", !(calendarUsage ?? "").isEmpty)
            check("appearance is automatic and ignores legacy selection",
                  model.settings.connectivityPreferences.uses3DModels)

            controller.start(polling: false)
            await settle(0.2)
            check("connectivity switch is enabled for QA", model.settings.bluetoothEnabled)

            let base = AudioDevice(id: "base", name: "AirPods Pro", left: 80, right: 79,
                                   single: nil, active: true, isAirPods: true, modelUID: "2014 4c")
            let low = AudioDevice(id: "low", name: "AirPods (unknown model)", left: 50, right: 50,
                                  single: nil, active: false, isAirPods: true, modelUID: "unknown")
            controller.verificationApply(snapshot([base, low]))
            await settle(0.2)
            check("first snapshot learns baseline without a toast", model.connectionToast == nil)
            check("first snapshot does not play a low-battery sound", sound.plays == 0)

            let pro = AudioDevice(id: "pro", name: "AirPods Pro 2", left: 84, right: 79,
                                  single: nil, active: true, isAirPods: true, modelUID: "2014 4c")
            controller.verificationApply(snapshot([base, low, pro]))
            await settle(0.55)
            check("new connected AirPods shows a toast", model.connectionToast?.id == pro.id)
            check("new connection is not low-battery", !model.connectionLowBattery)
            check("connection toast uses compact notification width",
                  model.visibleSize.width == model.nativeNotchSize.width
                  + NotchNotification.connectedAirPods.widthAddition(
                    notchOrSimulated: model.notchGeometry.hasPhysicalNotch || model.settings.forceSimulatedNotch))
            check("connection toast suppresses the lyric row", !model.showsCompactLyrics)
            try? capture("compact-connection-3d-layer")

            let arrival = model.connectionArrivalGeneration
            var late = pro
            late.modelUID = "2013 4c"
            late.left = 82
            late.right = 77
            controller.verificationApply(snapshot([base, low, late]))
            await settle(0.25)
            check("late model metadata updates the current toast", model.connectionToast?.movie == "airpods-3")
            check("late metadata does not replay arrival", model.connectionArrivalGeneration == arrival)

            check("automatic appearance keeps 3D enabled", model.settings.connectivityPreferences.uses3DModels)
            check("known model resolves a bundled movie name", model.connectionToast?.movie == "airpods-3")
            try? capture("compact-connection-3d-layer-not-in-bitmap")

            let unknown = AudioDevice(id: "unknown", name: "AirPods (unknown model)", left: nil,
                                     right: nil, single: nil, active: false, isAirPods: true,
                                     modelUID: "unknown")
            controller.verificationApply(snapshot([base, low, late, unknown]))
            await settle(0.35)
            check("unknown model falls back to a generic AirPods symbol", model.connectionToast?.symbol == "airpods")
            check("unknown model has no movie asset", model.connectionToast?.movie == nil)
            try? capture("compact-connection-unknown-symbol")

            var lowNow = low
            lowNow.left = 20
            lowNow.right = 20
            controller.verificationApply(snapshot([base, lowNow, late, unknown]))
            await settle(0.45)
            check("crossing 20% shows the low-battery state", model.connectionLowBattery)
            check("crossing 20% plays the low-battery sound once", sound.plays == 1)
            check("low-battery toast uses the recovered red-ring width",
                  model.visibleSize.width == model.nativeNotchSize.width
                  + NotchNotification.lowAirPodsBattery.widthAddition(
                    notchOrSimulated: model.notchGeometry.hasPhysicalNotch || model.settings.forceSimulatedNotch))
            check("zero is distinct from missing battery",
                  AudioDevice(id: "zero", name: "AirPods", left: 0, right: nil, single: nil,
                              active: false, isAirPods: true).battery == 0
                  && AudioDevice(id: "nil", name: "AirPods", left: nil, right: nil, single: nil,
                                 active: false, isAirPods: true).battery == nil)
            try? capture("compact-connection-low-battery")

            model.settings.bluetoothEnabled = false
            await settle(0.35)
            check("switch off clears devices and toast",
                  model.devices.isEmpty && model.connectionToast == nil)
            check("switch off stops an active low-battery sound", sound.stops >= 1)
            controller.verificationApply(snapshot([base, low, late]))
            await settle(0.2)
            check("late snapshot after switch off stays ignored", model.connectionToast == nil)

            model.settings.bluetoothEnabled = true
            await settle(0.3)
            controller.verificationApply(snapshot([base, low]))
            await settle(0.2)
            check("re-enable first snapshot is baseline only", model.connectionToast == nil)
            controller.verificationApply(snapshot([base, low, pro]))
            await settle(0.45)
            check("re-enable new connection is detected after baseline", model.connectionToast?.id == pro.id)

            let ids = coordinator.verificationScreenIDs
            if ids.count > 1 {
                coordinator.verificationActivateScreen(ids[1])
                await settle(0.4)
                check("active screen owns the connection surface",
                      coordinator.verificationActiveScreenID == ids[1] && model.connectionToast != nil)
                try? capture("active-connection")
                if let passive = coordinator.verificationSecondaryPanels.first {
                    try? capture("passive-connection-static", view: passive.view)
                }
            } else {
                check("injected two-screen connection QA exists", false)
            }

            coordinator.verificationActivateScreen(ids.first ?? "")
            await settle(0.3)
            model.title = "音乐与歌词恢复"
            model.artist = "合成状态"
            model.playing = true
            model.lyrics = LyricsDisplayState(status: .ready,
                timeline: LyricTimeline(lines: [
                    LyricLine(start: 0, text: "连接提示结束后的歌词", words: [
                        LyricWord(text: "连接提示", start: 0, duration: 1),
                        LyricWord(text: "结束后的歌词", start: 1, duration: 1)
                    ])
                ]), identity: LyricsTrackIdentity(title: model.title, artist: model.artist,
                                                  album: model.album, duration: model.duration))
            coordinator.expand()
            await settle(0.5)
            check("expanded music survives an active compact connection toast",
                  model.expanded && model.connectionToast != nil)
            try? capture("expanded-music-with-connection-pending")
            coordinator.collapse()
            await settle(0.35)
            check("collapse restores compact connection surface", model.connectionToast != nil)

            // A fresh prompt expires after the fixed five seconds and the
            // existing lyric row returns without another network request.
            let final = AudioDevice(id: "final", name: "AirPods Pro", left: 70, right: 70,
                                    single: nil, active: true, isAirPods: true, modelUID: "2014 4c")
            controller.verificationApply(snapshot([base, low, pro, final]))
            await settle(0.3)
            check("final prompt is visible before expiry (\(model.connectionToast?.id ?? "nil"), known=\(controller.verificationKnownIDs.sorted()))",
                  model.connectionToast?.id == final.id)
            try? capture("compact-connection-before-expiry")
            await settle(5.2)
            check("fixed five-second prompt expires", model.connectionToast == nil)
            check("lyrics return after connection prompt", model.showsCompactLyrics)
            try? capture("compact-connection-restored-lyrics")

            controller.stop()
            check("controller stop stops any active low-battery sound", sound.stops >= 1)
            let result: [String: Any] = [
                "passed": checks.allSatisfy { $0["passed"] as? Bool == true },
                "checks": checks,
                "rendering": "NSHostingView cacheDisplay; AVPlayer video layers may not appear in bitmap",
                "originalPixelParityVerified": false,
                "realBluetoothOrSoundUsed": false
            ]
            if let data = try? JSONSerialization.data(withJSONObject: result,
                                                       options: [.prettyPrinted, .sortedKeys]) {
                try? data.write(to: directory.appendingPathComponent("verification.json"))
            }
            NSApp.terminate(nil)
        }
    }
}
