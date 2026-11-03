import AppKit
import XCTest
@testable import Valora
import ReferenceCore

@MainActor
final class IndependentDeviceMediaReviewTests: XCTestCase {
    private final class ControlledMedia: SystemMediaProviding {
        var onSnapshot: (@MainActor (SystemMediaSnapshot?) -> Void)?
        var onError: (@MainActor (String) -> Void)?
        var initial: SystemMediaSnapshot?
        var completion: (@MainActor (Bool) -> Void)?
        func start() { onSnapshot?(initial) }
        func stop() {}
        func perform(_ arguments: [String], expected: SystemMediaSnapshot,
                     requireSameTrack: Bool, completion: @escaping @MainActor (Bool) -> Void) {
            self.completion = completion
        }
    }
    private func snapshot(_ title: String, playing: Bool) -> SystemMediaSnapshot {
        SystemMediaSnapshot(["bundleIdentifier":"com.test.player", "title":title,
            "artist":"Fixture", "album":"Test", "durationMicros":200_000_000,
            "elapsedTimeMicros":10_000_000, "playing":playing,
            "playbackRate": playing ? 1.0 : 0.0,
            "timestampEpochMicros":Date().timeIntervalSince1970 * 1_000_000,
            "contentItemIdentifier":title])!
    }
    private func model() -> (AppModel, UserDefaults, String) {
        let suite = "com.wangqing.valora.independent-device-media.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName:suite)!
        return (AppModel(settings:RevivalSettings(defaults:defaults)),defaults,suite)
    }
    func testNativeConnectSelectorCanArriveOffMainWithoutActorTrap() async {
        let events = ConnectivitySystemEvents()
        var delivered = 0
        events.onConnect = { _ in delivered += 1 }
        let receiver = ReviewCallbackObjects(target: events,
            notification: NSObject(), device: ReviewCallbackDevice())
        await withCheckedContinuation { (done: CheckedContinuation<Void, Never>) in
            DispatchQueue.global(qos: .utility).async {
                // Exercise the actual Objective-C entry thunk, as IOBluetooth
                // does on its coordinator queue. Stubs never touch hardware.
                _ = receiver.target.perform(NSSelectorFromString("bluetoothConnected:device:"),
                    with: receiver.notification, with: receiver.device)
                done.resume()
            }
        }
        await Task.yield()
        XCTAssertEqual(delivered, 0, "unregistered/late native callbacks must be rejected")
    }

    func testConnectBeforeFirstSnapshotIsNotSwallowedByBaseline() throws {
        let (model, defaults, suite) = model()
        defer { defaults.removePersistentDomain(forName:suite) }
        model.settings.bluetoothEnabled = true
        let controller = ConnectivityController(model,source:EmptyConnectivitySource(),sound:ReviewSilentSound())
        controller.start(polling:false); defer { controller.stop() }
        let events = try XCTUnwrap(Mirror(reflecting:controller).children.first(where:{$0.label == "systemEvents"})?.value as? ConnectivitySystemEvents)
        events.onConnect?("fixture")
        let device = AudioDevice(id:"fixture",name:"Fixture",left:70,right:75,single:nil,active:true,isAirPods:true,modelUID:"2013 4c")
        controller.verificationApply(ConnectedAudioSnapshot(devices:[device],output:"Fixture"))
        XCTAssertEqual(model.connectionToast?.id,"fixture","an explicit post-start connection is not a pre-existing baseline device")
    }

    func testReconnectWithLateModelKeepsArrivalUntilRecognized() throws {
        let (model, defaults, suite) = model()
        defer { defaults.removePersistentDomain(forName:suite) }
        model.settings.bluetoothEnabled = true
        let controller = ConnectivityController(model,source:EmptyConnectivitySource(),sound:ReviewSilentSound())
        controller.start(polling:false); defer { controller.stop() }
        var device = AudioDevice(id:"fixture",name:"Renamed headset",left:70,right:75,single:nil,active:true,isAirPods:true,modelUID:"2013 4c")
        controller.verificationApply(ConnectedAudioSnapshot(devices:[device],output:"Fixture"))
        let events = try XCTUnwrap(Mirror(reflecting:controller).children.first(where:{$0.label == "systemEvents"})?.value as? ConnectivitySystemEvents)
        events.onConnect?("fixture")
        device.isAirPods = false; device.modelUID = ""
        controller.verificationApply(ConnectedAudioSnapshot(devices:[device],output:"Fixture"))
        XCTAssertNil(model.connectionToast)
        device.isAirPods = true; device.modelUID = "2013 4c"
        controller.verificationApply(ConnectedAudioSnapshot(devices:[device],output:"Fixture"))
        XCTAssertEqual(model.connectionToast?.id,"fixture","early generic snapshot must not consume a real connection event")
        let generation = model.connectionArrivalGeneration
        controller.verificationApply(ConnectedAudioSnapshot(devices:[device],output:"Fixture"))
        XCTAssertEqual(model.connectionArrivalGeneration,generation)
    }

    func testActiveOutputRemovalAndReinsertionTriggersOnlyOnReinsert() throws {
        let (model, defaults, suite) = model()
        defer { defaults.removePersistentDomain(forName:suite) }
        model.settings.bluetoothEnabled = true
        let controller = ConnectivityController(model,source:EmptyConnectivitySource(),sound:ReviewSilentSound())
        controller.start(polling:false); defer { controller.stop() }
        var device = AudioDevice(id:"fixture",name:"AirPods",left:70,right:75,single:nil,
                                 active:true,isAirPods:true,modelUID:"2013 4c")
        controller.verificationApply(ConnectedAudioSnapshot(devices:[device],output:"AirPods"))
        XCTAssertNil(model.connectionToast, "startup active AirPods are baseline")
        device.active = false
        controller.verificationApply(ConnectedAudioSnapshot(devices:[device],output:"Built-in"))
        XCTAssertNil(model.connectionToast)
        device.active = true
        controller.verificationApply(ConnectedAudioSnapshot(devices:[device],output:"AirPods"))
        XCTAssertEqual(model.connectionToast?.id,"fixture","reinserting worn AirPods must trigger a new arrival")
        let generation = model.connectionArrivalGeneration
        controller.verificationApply(ConnectedAudioSnapshot(devices:[device],output:"AirPods"))
        XCTAssertEqual(model.connectionArrivalGeneration,generation,"same active route must not replay")
        device.modelUID = ""; device.isAirPods = false
        controller.verificationApply(ConnectedAudioSnapshot(devices:[device],output:"AirPods"))
        XCTAssertEqual(model.connectionToast?.movie, "airpods-3",
                       "transient missing metadata must not change the current AirPods artwork")
    }

    func testPendingConnectionExpiresAndDoesNotReplayAsLateMetadata() throws {
        let (model, defaults, suite) = model()
        defer { defaults.removePersistentDomain(forName:suite) }
        model.settings.bluetoothEnabled = true
        var now: TimeInterval = 0
        let controller = ConnectivityController(model,source:EmptyConnectivitySource(),sound:ReviewSilentSound(),clock:{ now })
        controller.start(polling:false); defer { controller.stop() }
        var device = AudioDevice(id:"fixture",name:"Fixture",left:nil,right:nil,single:nil,active:true,isAirPods:false)
        controller.verificationApply(ConnectedAudioSnapshot(devices:[device],output:"Fixture"))
        let events = try XCTUnwrap(Mirror(reflecting:controller).children.first(where:{$0.label == "systemEvents"})?.value as? ConnectivitySystemEvents)
        events.onConnect?("fixture")
        now = 11
        device.isAirPods = true; device.modelUID = "2013 4c"
        controller.verificationApply(ConnectedAudioSnapshot(devices:[device],output:"Fixture"))
        XCTAssertNil(model.connectionToast,"expired connection intent must not become a much later surprise arrival")
    }

    func testFailedOldToggleCannotOverwriteNewTrackSnapshot() {
        let (model, defaults, suite) = model()
        defer { defaults.removePersistentDomain(forName:suite) }
        let source = ControlledMedia(); source.initial = snapshot("old",playing:true)
        let controller = MediaController(model,system:source)
        controller.start(); defer { controller.stop() }
        controller.command(2)
        source.onSnapshot?(snapshot("new",playing:false))
        source.completion?(false)
        XCTAssertEqual(model.title,"new")
        XCTAssertFalse(model.playing,"old failure must not restore the previous track's playing state")
        XCTAssertNil(model.mediaError,"old failure must not contaminate a newly received authoritative track")
    }
    func testFailedToggleAfterStopCannotMutateModel() {
        let (model, defaults, suite) = model()
        defer { defaults.removePersistentDomain(forName:suite) }
        let source = ControlledMedia(); source.initial = snapshot("old",playing:true)
        let controller = MediaController(model,system:source)
        controller.start(); controller.command(2); controller.stop()
        let playing = model.playing; let error = model.mediaError
        source.completion?(false)
        XCTAssertEqual(model.playing,playing,"stopped media session must reject command completions")
        XCTAssertEqual(model.mediaError,error)
    }
    func testConnectDuringReadSchedulesFreshReadWithoutWaitingForPoll() async throws {
        let (model, defaults, suite) = model()
        defer { defaults.removePersistentDomain(forName:suite) }
        model.settings.bluetoothEnabled = true
        let source = HeldConnectedSource()
        let controller = ConnectivityController(model,source:source,sound:ReviewSilentSound())
        controller.start(polling:false); defer { controller.stop() }
        controller.refresh()
        for _ in 0..<50 { if !model.devices.isEmpty { break }; try? await Task.sleep(for:.milliseconds(10)) }
        XCTAssertEqual(model.devices.count,1)
        controller.refresh()
        for _ in 0..<50 { if await source.count >= 2 { break }; try? await Task.sleep(for:.milliseconds(10)) }
        let events = try XCTUnwrap(Mirror(reflecting:controller).children.first(where:{$0.label == "systemEvents"})?.value as? ConnectivitySystemEvents)
        events.onConnect?("fixture")
        await source.release()
        try? await Task.sleep(for:.milliseconds(200))
        let count = await source.count
        XCTAssertEqual(count,3,"event during in-flight native read must coalesce one fresh query, not wait for fallback poll")
    }
}
private actor HeldConnectedSource: ConnectedAudioSource {
    private(set) var count = 0
    private var continuation: CheckedContinuation<ConnectedAudioSnapshot,Never>?
    private func value() -> ConnectedAudioSnapshot {
        ConnectedAudioSnapshot(devices:[AudioDevice(id:"fixture",name:"Fixture",left:70,right:75,single:nil,active:true,isAirPods:true,modelUID:"2013 4c")],output:"Fixture")
    }
    func snapshot() async -> ConnectedAudioSnapshot {
        count += 1
        if count == 2 { return await withCheckedContinuation { continuation = $0 } }
        return value()
    }
    func release() { let pending = continuation; continuation = nil; pending?.resume(returning:value()) }
}
@MainActor private final class ReviewSilentSound: LowBatterySoundPlaying {
    func playLowBattery() {}
}

private final class ReviewCallbackObjects: @unchecked Sendable {
    let target: NSObject
    let notification: NSObject
    let device: NSObject
    init(target: NSObject, notification: NSObject, device: NSObject) {
        self.target = target; self.notification = notification; self.device = device
    }
}
private final class ReviewCallbackDevice: NSObject {
    @objc var addressString: String { "00-00-00-00-00-01" }
}
