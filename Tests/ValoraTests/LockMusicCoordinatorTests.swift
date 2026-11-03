import AppKit
import Combine
import SwiftUI
import XCTest
@testable import Valora
import ReferenceCore

/// Fully isolated adapter doubles. No NSWindow, NSHostingView, notification
/// center, Space, NSSound or wall-clock wait is created by these tests.
@MainActor
final class LockMusicCoordinatorTests: XCTestCase {
    final class FakeWindow: LockPresentationWindow {
        let size: CGSize
        var frame: CGRect
        var isVisible = false
        var rootView: AnyView?
        var closed = false
        var sharingType: NSWindow.SharingType = .readOnly
        init(size: CGSize) {
            self.size = size
            frame = CGRect(origin: .zero, size: size)
        }
        var windowNumber: Int { 100 + Int(size.width) }
        func setRootView(_ view: AnyView) { rootView = view }
        func clearRootView() { rootView = nil }
        func setFrameOrigin(_ origin: CGPoint) { frame.origin = origin }
        func setSharingType(_ type: NSWindow.SharingType) { sharingType = type }
        func orderFrontRegardless() { isVisible = true }
        func orderOut() { isVisible = false }
        func close() { closed = true }
    }

    final class FakeWindowFactory: LockPresentationWindowFactory {
        var windows: [FakeWindow] = []
        func makeWindow(size: CGSize, level: NSWindow.Level, ignoresMouseEvents: Bool) -> any LockPresentationWindow {
            let window = FakeWindow(size: size)
            windows.append(window)
            return window
        }
    }

    final class FakeSpace: LockPresentationSpace {
        var attachResult = true
        var migrateResult = true
        /// nil keeps the legacy add-only meaning used by the older regressions.
        var exclusiveResult: [String: Any]?
        var exclusiveResultsByWindow: [Int: [String: Any]] = [:]
        var exclusiveCalls: [Int] = []
        var attached: [Int] = []
        var detached: [Int] = []
        func attachWindowNumber(_ number: Int) -> Bool {
            if attachResult { attached.append(number) }
            return attachResult
        }
        func detachWindowNumber(_ number: Int) { detached.append(number) }
        var spaceID: UInt64 = 145
        func diagnostic() -> [AnyHashable: Any] { [:] }
        func windowSpaceIDs(_ number: Int) -> [NSNumber]? { [NSNumber(value: spaceID)] }
        func migrateWindowNumberToOwnedSpace(_ number: Int) -> Bool {
            guard migrateResult else { return false }
            attached.append(number)
            return true
        }
        func migrateWindowNumberExclusively(_ number: Int) -> [String: Any] {
            exclusiveCalls.append(number)
            if let result = exclusiveResultsByWindow[number] { return result }
            if let exclusiveResult { return exclusiveResult }
            return ["ok": migrateWindowNumberToOwnedSpace(number), "reason": "fake-default"]
        }
    }

    final class FakeNotch: LockNotchWindow {
        var windowNumber: Int
        init(_ number: Int) { windowNumber = number }
    }

    final class FakeEventSource: LockSystemEventSource {
        var onLocked: (@MainActor @Sendable (Bool) -> Void)?
        var onSleep: (@MainActor @Sendable () -> Void)?
        var onWake: (@MainActor @Sendable () -> Void)?
        var onScreensChanged: (@MainActor @Sendable () -> Void)?
        var startCount = 0
        var stopCount = 0
        func start() { startCount += 1 }
        func stop() { stopCount += 1 }
        func deliverLocked(_ value: Bool) { onLocked?(value) }
        func deliverSleep() { onSleep?() }
        func deliverWake() { onWake?() }
    }

    final class FakeTask: LockScheduledTask {
        let delay: TimeInterval
        var action: (@MainActor @Sendable () -> Void)?
        var cancelled = false
        var fired = false
        init(delay: TimeInterval, action: @escaping @MainActor @Sendable () -> Void) {
            self.delay = delay
            self.action = action
        }
        func cancel() { cancelled = true; action = nil }
        func fire() {
            guard !cancelled, !fired else { return }
            fired = true
            action?()
        }
    }

    final class FakeScheduler: LockScheduling {
        var tasks: [FakeTask] = []
        func schedule(after seconds: TimeInterval,
                      _ action: @escaping @MainActor @Sendable () -> Void) -> any LockScheduledTask {
            let task = FakeTask(delay: seconds, action: action)
            tasks.append(task)
            return task
        }
    }

    final class FakeCollapse {
        var completions: [() -> Void] = []
        func runNext() {
            guard !completions.isEmpty else { return }
            completions.removeFirst()()
        }
        func runAll() {
            while !completions.isEmpty { runNext() }
        }
    }

    final class GeometryAnimatorSpy: LockGeometryAnimating {
        var commits = 0
        var pending: [(changes: () -> Void, completion: () -> Void)] = []
        func animate(_ changes: @escaping @MainActor () -> Void,
                     completion: @escaping @MainActor () -> Void) {
            commits += 1
            changes()
            pending.append((changes, completion))
        }
        func completeNext() {
            guard !pending.isEmpty else { return }
            pending.removeFirst().completion()
        }
    }

    final class SoundSpy: LockSoundPlaying {
        var lockCount = 0
        var unlockCount = 0
        var stopCount = 0
        func playLock() { lockCount += 1 }
        func playUnlock() { unlockCount += 1 }
        func stop() { stopCount += 1 }
    }

    private var suite = ""
    private var defaults: UserDefaults!
    private var settings: RevivalSettings!
    private var model: AppModel!
    private var factory: FakeWindowFactory!
    private var space: FakeSpace!
    private var events: FakeEventSource!
    private var scheduler: FakeScheduler!
    private var collapse: FakeCollapse!
    private var geometry: GeometryAnimatorSpy!
    private var sound: SoundSpy!
    private var notch: FakeNotch!
    private var notchUpdates: CurrentValueSubject<Int?, Never>!
    private var now: TimeInterval = 0
    private var sessionLocked = false

    override func setUp() {
        super.setUp()
        suite = "com.wangqing.valora.lock.isolated.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(["enableLockScreen": true,
                      "allowNowPlayingWidgetWhenLocked": true,
                      "allowConnectivityWidgetWhenLocked": true,
                      "playSoundOnLock": true,
                      "playSoundOnUnlock": true],
                     forKey: "referenceSettingsUI")
        settings = RevivalSettings(defaults: defaults)
        model = AppModel(settings: settings)
        model.title = "Fixture"
        model.artist = "Fixture artist"
        model.playing = true
        factory = FakeWindowFactory()
        space = FakeSpace()
        events = FakeEventSource()
        scheduler = FakeScheduler()
        collapse = FakeCollapse()
        geometry = GeometryAnimatorSpy()
        sound = SoundSpy()
        notch = FakeNotch(11)
        notchUpdates = CurrentValueSubject<Int?, Never>(11)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    private func makeCoordinator(useProductionCollapse: Bool = false) -> LockMusicCoordinator {
        LockMusicCoordinator(model,
            notchWindowProvider: { [weak self] in self?.notch },
            notchWindowUpdates: notchUpdates.eraseToAnyPublisher(),
            windowFactory: factory,
            overlayWindowFactory: factory,
            overlayFrameProvider: { [weak self] in self?.model.notchGeometry.hasPhysicalNotch == true ? CGRect(x: 0, y: 0, width: 1728, height: 1117) : CGRect(x: 0, y: 0, width: 1728, height: 1117) },
            spaceFactory: { [weak self] in self?.space },
            eventSource: events,
            scheduler: scheduler,
            collapsePresentation: useProductionCollapse ? nil : { [weak self] completion in
                self?.collapse.completions.append(completion)
            },
            geometryAnimator: geometry,
            clock: { [weak self] in self?.now ?? 0 },
            sessionLocked: { [weak self] in self?.sessionLocked ?? false },
            sound: sound)
    }

    private func drain() async {
        await Task.yield()
        await Task.yield()
        await Task.yield()
    }

    private func fireDelay(_ delay: TimeInterval) {
        scheduler.tasks.first(where: { $0.delay == delay && !$0.cancelled && !$0.fired })?.fire()
    }

    private func completeLockStages() {
        collapse.runNext()
        fireDelay(0)
        geometry.completeNext()
    }

    func testPanelBoundsUseInjectedWindowFactory() {
        let coordinator = makeCoordinator()
        coordinator.setEnabled(true)
        XCTAssertEqual(coordinator.panel.frame.size, CGSize(width: 385, height: 325))
        XCTAssertEqual(coordinator.informationPanel.frame.size, CGSize(width: 360, height: 94))
        XCTAssertEqual(factory.windows.count, 2)
        coordinator.stop()
    }

    func testSoundEdgesUseSpyAndInitialLockedBaselineDoesNotPlay() {
        sessionLocked = true
        let coordinator = makeCoordinator()
        coordinator.setEnabled(true)
        XCTAssertEqual(sound.lockCount, 0, "startup locked state establishes baseline only")
        events.deliverLocked(false)
        XCTAssertEqual(sound.unlockCount, 1)
        events.deliverLocked(false)
        XCTAssertEqual(sound.unlockCount, 1, "same-state event must not replay")
        events.deliverLocked(true)
        XCTAssertEqual(sound.lockCount, 1)
        coordinator.stop()
    }

    func testDefaultLockSoundIsOffAndUnlockStaysOn() {
        defaults.set(["enableLockScreen": true,
                      "allowNowPlayingWidgetWhenLocked": true,
                      "allowConnectivityWidgetWhenLocked": true,
                      "playSoundOnLock": false,
                      "playSoundOnUnlock": true], forKey: "referenceSettingsUI")
        settings.reloadPreferences()
        let coordinator = makeCoordinator()
        coordinator.setEnabled(true)
        events.deliverLocked(true)
        XCTAssertEqual(sound.lockCount, 0)
        events.deliverLocked(false)
        XCTAssertEqual(sound.unlockCount, 1)
        coordinator.stop()
    }

    func testDisableStopsPresentationAndRestoresNormalMusicState() {
        let coordinator = makeCoordinator()
        coordinator.setEnabled(true)
        events.deliverLocked(true)
        XCTAssertTrue(model.isSessionLocked)
        coordinator.setEnabled(false)
        XCTAssertFalse(coordinator.enabled)
        XCTAssertFalse(model.isSessionLocked)
        XCTAssertFalse(model.showsLockActivity)
        XCTAssertTrue(factory.windows.allSatisfy(\.closed))
        XCTAssertGreaterThanOrEqual(sound.stopCount, 1)
        coordinator.stop()
    }

    func testStopStartRebuildsPausedDeadlineAndSleepState() async {
        sessionLocked = true
        model.playing = false
        let coordinator = makeCoordinator()
        coordinator.setEnabled(true)
        await drain()
        let firstDeadline = scheduler.tasks.filter { $0.delay == 600 }
        XCTAssertEqual(firstDeadline.count, 1, "paused locked start must schedule one 600s deadline")

        // Emulate a deadline that has already expired, then reuse the same
        // coordinator via the AppDelegate setEnabled path.
        now = 600
        scheduler.tasks.filter { $0.delay == 600 }.first?.fire()
        XCTAssertFalse(coordinator.visible)
        coordinator.setEnabled(false)
        now = 900
        coordinator.setEnabled(true)
        await drain()
        let secondDeadline = scheduler.tasks.filter { $0.delay == 600 }
        XCTAssertEqual(secondDeadline.count, 2, "same input after restart must establish a fresh deadline")
        XCTAssertTrue(secondDeadline.last?.fired == false)

        // Sleeping state must not survive stop/start.
        events.deliverSleep()
        XCTAssertFalse(coordinator.visible)
        coordinator.setEnabled(false)
        now = 901
        coordinator.setEnabled(true)
        await drain()
        XCTAssertTrue(coordinator.visible, "new session must not inherit the old sleeping state")
        coordinator.stop()
    }

    func testIndependentCompactMusicDoesNotSkipCollapseOnRealPresenterPath() {
        let coordinator = makeCoordinator(useProductionCollapse: true)
        coordinator.setEnabled(true)
        defer { coordinator.stop() }
        XCTAssertFalse(model.expanded)
        XCTAssertTrue(model.showsMusicActivity)
        XCTAssertGreaterThan(model.visibleSize.width, model.notchGeometry.compact.width)
        events.deliverLocked(true)
        XCTAssertEqual(model.lockIndicator.phase, .locking,
                       "compact music has side wings too: the production collapsed-player shortcut must not immediately commit the lock badge before those wings retract")
        XCTAssertFalse(model.showsLockActivity)
    }

    func testCompactProductionCollapsePathUsesNeutralBaseBeforeBadge() {
        let coordinator = makeCoordinator(useProductionCollapse: true)
        coordinator.setEnabled(true)
        defer { coordinator.stop() }
        XCTAssertFalse(model.expanded)
        XCTAssertGreaterThan(model.visibleSize.width, model.notchGeometry.compact.width)
        events.deliverLocked(true)
        XCTAssertEqual(model.lockIndicator.phase, .locking)
        fireDelay(0)
        XCTAssertEqual(model.lockIndicator.phase, .neutralizing)
        XCTAssertEqual(model.visibleSize, model.notchGeometry.compact)
        XCTAssertFalse(model.showsMusicActivity)
        XCTAssertFalse(model.showsLockActivity)
        geometry.completeNext()
        XCTAssertEqual(model.lockIndicator.phase, .locked)
        XCTAssertTrue(model.showsLockActivity)
    }

    func testIndependentUnlockRetractsBadgeBeforeRestoringMusicGeometry() {
        sessionLocked = true
        let coordinator = makeCoordinator()
        coordinator.setEnabled(true)
        defer { coordinator.stop() }
        events.deliverLocked(false)
        XCTAssertEqual(model.lockIndicator.phase, .unlocking)
        scheduler.tasks.first(where: { $0.delay == 0.8 && !$0.cancelled })?.fire()
        XCTAssertEqual(model.lockIndicator.phase, .restoring)
        XCTAssertFalse(model.showsMusicActivity,
                       "after open-lock glyph, a distinct neutral collapse must precede restoring music; directly showing music only crossfades content")
        XCTAssertEqual(model.visibleSize, model.notchGeometry.compact,
                       "the unlock collapse stage must use the neutral notch size before expanding music again")
    }

    func testLockWaitsForBoundedNormalCollapseBeforeShowingBadge() {
        let coordinator = makeCoordinator()
        coordinator.setEnabled(true)
        let topBefore = model.contour.topInset
        events.deliverLocked(true)
        XCTAssertEqual(model.lockIndicator.phase, .locking)
        XCTAssertTrue(model.isSessionLocked)
        XCTAssertTrue(model.isLockTransitioning)
        XCTAssertTrue(model.showsMusicActivity, "normal music remains mounted while it collapses")
        XCTAssertFalse(model.showsLockActivity, "the badge must not appear before the collapse completion")
        XCTAssertEqual(collapse.completions.count, 1)
        XCTAssertEqual(model.contour.topInset, topBefore, "transition must stay top-anchored")
        collapse.runNext()
        XCTAssertEqual(model.lockIndicator.phase, .locking,
                       "the compact production completion must not jump directly to the badge")
        fireDelay(0)
        XCTAssertEqual(model.lockIndicator.phase, .neutralizing)
        XCTAssertTrue(model.isLockNeutralGeometry)
        XCTAssertFalse(model.showsMusicActivity)
        XCTAssertFalse(model.showsLockActivity)
        XCTAssertEqual(model.visibleSize, model.notchGeometry.compact,
                       "neutral stage must retract compact music side wings before badge expansion")
        model.showsOutputVolume = true
        model.connectionToast = AudioDevice(id: "toast", name: "AirPods", left: 70, right: 70,
                                             single: nil, active: true, isAirPods: true,
                                             modelUID: "2013 4c")
        model.isPointerInside = true
        XCTAssertEqual(model.visibleSize, model.notchGeometry.compact,
                       "neutral geometry must suppress output height, toast width and peek")
        XCTAssertEqual(model.hoverScale, CGSize(width: 1, height: 1),
                       "neutral geometry must suppress hover deformation")
        XCTAssertEqual(model.contour.topInset, topBefore)
        geometry.completeNext()
        XCTAssertEqual(model.lockIndicator.phase, .locked)
        XCTAssertTrue(model.isSessionLocked)
        XCTAssertTrue(model.showsLockActivity)
        XCTAssertFalse(model.showsMusicActivity)
        XCTAssertEqual(model.contour.topInset, topBefore)
        coordinator.stop()
    }

    func testUnlockShowsOpenGlyphThenRestoresNormalMusicBeforeBadgeHidden() {
        let coordinator = makeCoordinator()
        coordinator.setEnabled(true)
        events.deliverLocked(true)
        completeLockStages()
        XCTAssertEqual(model.lockIndicator.phase, .locked)
        let musicNumber = coordinator.panel.windowNumber
        events.deliverLocked(false)
        XCTAssertEqual(model.lockIndicator.phase, .unlocking)
        XCTAssertTrue(model.isSessionLocked, "normal music waits for the open-glyph stage")
        XCTAssertFalse(coordinator.visible, "lock-only music card is removed at unlock start")
        XCTAssertTrue(space.detached.contains(musicNumber), "music panel detach is immediate")
        let unlockTask = scheduler.tasks.first(where: { $0.delay == 0.8 && !$0.cancelled })
        unlockTask?.fire()
        XCTAssertEqual(model.lockIndicator.phase, .restoring)
        XCTAssertTrue(model.isSessionLocked, "session stays locked while the badge retracts")
        XCTAssertFalse(model.showsMusicActivity,
                       "music must not return until the neutral base stage completes")
        XCTAssertEqual(model.visibleSize, model.notchGeometry.compact)
        geometry.completeNext()
        XCTAssertEqual(model.lockIndicator.phase, .hidden)
        XCTAssertFalse(model.isSessionLocked)
        XCTAssertTrue(model.showsMusicActivity, "latest music restores after the neutral stage")
        XCTAssertGreaterThan(model.visibleSize.width, model.notchGeometry.compact.width)
        coordinator.stop()
    }

    func testSleepCancelsQueuedNeutralStage() {
        let coordinator = makeCoordinator()
        coordinator.setEnabled(true)
        events.deliverLocked(true)
        collapse.runNext()
        fireDelay(0)
        XCTAssertEqual(model.lockIndicator.phase, .neutralizing)
        events.deliverSleep()
        XCTAssertEqual(model.lockIndicator.phase, .hidden)
        geometry.completeNext()
        XCTAssertEqual(model.lockIndicator.phase, .hidden,
                       "a neutral completion queued before sleep must not resurrect the lock stage")
        events.deliverWake()
        XCTAssertEqual(model.lockIndicator.phase, .locked)
        coordinator.stop()
    }

    func testRapidLockUnlockRejectsStaleLockCompletion() {
        let coordinator = makeCoordinator()
        coordinator.setEnabled(true)
        events.deliverLocked(true)
        XCTAssertEqual(model.lockIndicator.phase, .locking)
        events.deliverLocked(false)
        XCTAssertEqual(model.lockIndicator.phase, .hidden)
        XCTAssertFalse(model.isSessionLocked)
        collapse.runAll()
        fireDelay(0)
        XCTAssertEqual(model.lockIndicator.phase, .hidden, "old collapse completion must not resurrect the badge")
        events.deliverLocked(true)
        XCTAssertEqual(model.lockIndicator.phase, .locking)
        completeLockStages()
        XCTAssertEqual(model.lockIndicator.phase, .locked)
        coordinator.stop()
    }

    func testOldEventCallbacksAreRejectedAcrossStopStartAndNewOnesWork() async {
        sessionLocked = true
        let coordinator = makeCoordinator()
        coordinator.setEnabled(true)
        let oldLock = events.onLocked
        let oldSleep = events.onSleep
        let oldUnlock = oldLock
        coordinator.setEnabled(false)
        coordinator.setEnabled(true)
        await drain()
        oldLock?(false)
        oldLock?(true)
        oldSleep?()
        XCTAssertEqual(sound.lockCount, 0)
        XCTAssertEqual(sound.unlockCount, 0)
        XCTAssertTrue(model.isSessionLocked)
        XCTAssertTrue(coordinator.visible, "old sleep/unlock callbacks must not poison the new session")

        events.deliverLocked(false)
        XCTAssertTrue(model.isSessionLocked, "unlock glyph stage keeps normal content out")
        XCTAssertEqual(sound.unlockCount, 1, "valid new event must still work")
        XCTAssertFalse(coordinator.visible)
        scheduler.tasks.first(where: { $0.delay == 0.8 && !$0.cancelled && !$0.fired })?.fire()
        XCTAssertTrue(model.isSessionLocked, "neutral retract stage keeps the session locked")
        XCTAssertEqual(model.lockIndicator.phase, .restoring)
        geometry.completeNext()
        XCTAssertFalse(model.isSessionLocked, "restore completion releases the normal music surface")
        coordinator.stop()
    }

    func testInformationPublishesNilDeviceBatteryAndOffTransitions() async {
        sessionLocked = true
        let coordinator = makeCoordinator()
        coordinator.setEnabled(true)
        var values: [AudioDevice?] = []
        let token = coordinator.$informationAirPods.sink { values.append($0) }
        defer { token.cancel() }
        await drain()
        XCTAssertEqual(coordinator.informationAirPods, nil)

        var device = AudioDevice(id: "fixture", name: "AirPods", left: 70, right: 75,
                                 single: nil, active: true, isAirPods: true, modelUID: "2013 4c")
        model.devices = [device]
        await drain()
        XCTAssertEqual(coordinator.informationAirPods?.id, "fixture")
        XCTAssertEqual(coordinator.informationAirPods?.battery, 70)

        device.left = 40; device.right = 45
        model.devices = [device]
        await drain()
        XCTAssertEqual(coordinator.informationAirPods?.battery, 40, "same ID battery change must publish")

        device.modelUID = "2014 4c"
        model.devices = [device]
        await drain()
        XCTAssertEqual(coordinator.informationAirPods?.modelUID, "2014 4c",
                       "same ID model change must publish")

        model.devices = []
        await drain()
        XCTAssertNil(coordinator.informationAirPods)

        model.devices = [device]
        await drain()
        XCTAssertEqual(coordinator.informationAirPods?.id, "fixture")
        var preferenceValues = defaults.dictionary(forKey: "referenceSettingsUI") ?? [:]
        preferenceValues["allowConnectivityWidgetWhenLocked"] = false
        defaults.set(preferenceValues, forKey: "referenceSettingsUI")
        settings.reloadPreferences()
        await drain()
        XCTAssertNil(coordinator.informationAirPods, "device sub-switch off must publish nil")
        coordinator.stop()
        XCTAssertFalse(preferenceValues.isEmpty)
    }

    func testInformationDeviceToNilAndGlobalOff() async {
        sessionLocked = true
        let coordinator = makeCoordinator()
        coordinator.setEnabled(true)
        let device = AudioDevice(id: "fixture", name: "AirPods", left: nil, right: nil,
                                 single: nil, active: true, isAirPods: true, modelUID: "2013 4c")
        model.devices = [device]
        await drain()
        XCTAssertEqual(coordinator.informationAirPods?.id, "fixture")
        XCTAssertNil(coordinator.informationAirPods?.battery)
        model.devices = []
        await drain()
        XCTAssertNil(coordinator.informationAirPods)
        model.devices = [device]
        await drain()
        defaults.set(["enableLockScreen": false,
                      "allowNowPlayingWidgetWhenLocked": true,
                      "allowConnectivityWidgetWhenLocked": true], forKey: "referenceSettingsUI")
        settings.reloadPreferences()
        await drain()
        XCTAssertNil(coordinator.informationAirPods)
        coordinator.stop()
    }

    func testNowPlayingGlobalSwitchHidesAndRestoresWithoutMediaSnapshot() async {
        sessionLocked = true
        let coordinator = makeCoordinator()
        coordinator.setEnabled(true)
        XCTAssertTrue(coordinator.visible)
        model.settings.nowPlayingEnabled = false
        await drain()
        XCTAssertFalse(coordinator.visible)
        XCTAssertTrue(model.isSessionLocked, "lock indicator remains independent")
        model.settings.nowPlayingEnabled = true
        await drain()
        XCTAssertTrue(coordinator.visible, "restoring global music reopens the lock card")
        coordinator.stop()
    }

    func testRealLockUsesOverlayInsteadOfPrimaryNotchWindow() async {
        sessionLocked = true
        let coordinator = makeCoordinator()
        coordinator.setEnabled(true)
        events.deliverLocked(true)
        await drain()
        XCTAssertTrue(model.lockOverlayReady)
        XCTAssertTrue(space.attached.contains(724), "the dedicated lock overlay is attached")
        notch = FakeNotch(22)
        notchUpdates.send(22)
        await drain()
        XCTAssertTrue(model.lockOverlayReady)
        XCTAssertFalse(space.attached.contains(22), "primary notch is not attached while overlay owns the surface")
        coordinator.stop()
        XCTAssertTrue(space.detached.contains(724))
    }

    func testIndependentUnlockDetachesMusicAndInformationWindows() async {
        sessionLocked = true
        model.devices = [AudioDevice(id: "fixture", name: "AirPods", left: 70, right: 75,
                                    single: nil, active: true, isAirPods: true, modelUID: "2013 4c")]
        let coordinator = makeCoordinator()
        coordinator.setEnabled(true)
        defer { coordinator.stop() }
        await drain()
        let musicNumber = coordinator.panel.windowNumber
        let informationNumber = coordinator.informationPanel.windowNumber
        XCTAssertTrue(space.attached.contains(musicNumber))
        XCTAssertTrue(space.attached.contains(informationNumber))
        events.deliverLocked(false)
        await drain()
        XCTAssertFalse(coordinator.panel.isVisible)
        XCTAssertTrue(space.detached.contains(musicNumber), "unlock must remove the music window from the owned lock Space, not merely order it out")
        XCTAssertTrue(space.detached.contains(informationNumber))
        XCTAssertTrue(model.lockOverlayReady, "the dedicated overlay stays mounted for its unlocking animation")
        scheduler.tasks.first(where: { $0.delay == 0.8 && !$0.cancelled && !$0.fired })?.fire()
        XCTAssertTrue(model.lockOverlayReady,
                      "neutral animation still owns the lock overlay after the open glyph")
        geometry.completeNext()
        XCTAssertTrue(space.detached.contains(724), "neutral completion releases the lock overlay")
    }

    func testIndependentNeutralGeometryRetainsNotchSpaceOwnership() {
        sessionLocked = true
        let coordinator = makeCoordinator()
        coordinator.setEnabled(true)
        defer { coordinator.stop() }
        XCTAssertTrue(model.lockOverlayReady)
        events.deliverLocked(false)
        fireDelay(0.8)
        XCTAssertEqual(model.lockIndicator.phase, .restoring)
        XCTAssertTrue(model.isSessionLocked)
        XCTAssertTrue(model.lockOverlayReady,
                      "neutral geometry still animates in the dedicated lock overlay")
        XCTAssertFalse(space.detached.contains(724),
                       "detach only after the neutral collapse/restore boundary finishes")
        geometry.completeNext()
        XCTAssertFalse(model.lockOverlayReady)
    }

    func testIndependentLockNeutralAttachesBeforeShowingBadge() {
        let coordinator = makeCoordinator()
        coordinator.setEnabled(true)
        defer { coordinator.stop() }
        events.deliverLocked(true)
        collapse.runNext()
        fireDelay(0)
        XCTAssertEqual(model.lockIndicator.phase, .neutralizing)
        XCTAssertTrue(model.isSessionLocked)
        XCTAssertTrue(model.lockOverlayReady,
                      "the compact-collapse stage must own the dedicated lock overlay before its badge appears")
    }

    func testNeutralCompletionIsOneShotAndOldCallbackCannotRelock() {
        let coordinator = makeCoordinator()
        coordinator.setEnabled(true)
        events.deliverLocked(true)
        collapse.runNext()
        fireDelay(0)
        XCTAssertEqual(model.lockIndicator.phase, .neutralizing)
        XCTAssertEqual(geometry.pending.count, 1)
        // Unlock before the neutral animation completes; the pending callback
        // must not resurrect a badge on a later dispatch.
        events.deliverLocked(false)
        XCTAssertEqual(model.lockIndicator.phase, .hidden)
        geometry.completeNext()
        XCTAssertEqual(model.lockIndicator.phase, .hidden)
        XCTAssertFalse(model.isSessionLocked)
        // A fresh lock creates a fresh completion; completing it once advances
        // exactly once, and a second completion has no pending target.
        events.deliverLocked(true)
        collapse.runNext()
        fireDelay(0)
        XCTAssertEqual(model.lockIndicator.phase, .neutralizing)
        geometry.completeNext()
        XCTAssertEqual(model.lockIndicator.phase, .locked)
        geometry.completeNext()
        XCTAssertEqual(model.lockIndicator.phase, .locked)
        coordinator.stop()
    }

    func testSpaceFailureFailsClosed() async {
        space.attachResult = false
        sessionLocked = true
        let coordinator = makeCoordinator()
        coordinator.setEnabled(true)
        events.deliverLocked(true)
        await drain()
        XCTAssertFalse(model.lockNotchMounted)
        XCTAssertFalse(coordinator.panel.isVisible)
        coordinator.stop()
    }

    func testOverlayFailureKeepsPrimaryFallbackVisible() async {
        space.migrateResult = false
        sessionLocked = true
        let coordinator = makeCoordinator()
        coordinator.setEnabled(true)
        events.deliverLocked(true)
        await drain()
        XCTAssertFalse(model.lockOverlayReady)
        XCTAssertTrue(model.lockNotchMounted, "primary remains the known fallback when overlay migration fails")
        XCTAssertTrue(space.attached.contains(11))
        coordinator.stop()
    }

    func testIndependentOverlayFailureDoesNotRecreateOnOrdinaryRefresh() async {
        space.migrateResult = false
        sessionLocked = true
        let coordinator = makeCoordinator()
        coordinator.setEnabled(true)
        await drain()
        let preparedCount = factory.windows.count
        coordinator.refresh()
        coordinator.refresh()
        XCTAssertEqual(factory.windows.count, preparedCount,
            "fallback must stay stable instead of allocating/closing a new window on each media refresh")
        XCTAssertFalse(model.lockOverlayReady)
        XCTAssertTrue(model.lockNotchMounted)
        coordinator.stop()
    }

    func testNotchMountPrefersOwnedSpaceOnlyAndSkipsAddOnly() async {
        space.exclusiveResult = ["ok": true, "reason": "captured"]
        // Keep the dedicated overlay out of the way so the primary mount path is
        // the one under test.
        space.exclusiveResultsByWindow = [724: ["ok": false, "reason": "not-exclusive"]]
        sessionLocked = true
        let coordinator = makeCoordinator()
        coordinator.setEnabled(true)
        events.deliverLocked(true)
        await drain()
        XCTAssertTrue(space.exclusiveCalls.contains(11),
                      "the primary notch is moved into the owned Space only")
        XCTAssertFalse(space.attached.contains(11),
                       "the ordinary desktop membership is not re-added, so the panel cannot ride the lock zoom")
        XCTAssertTrue(model.lockNotchMounted)
        coordinator.stop()
    }

    func testNotchMountFallsBackToAddOnlyWhenExclusiveIsRefused() async {
        space.exclusiveResult = ["ok": false, "reason": "not-exclusive"]
        sessionLocked = true
        let coordinator = makeCoordinator()
        coordinator.setEnabled(true)
        events.deliverLocked(true)
        await drain()
        XCTAssertTrue(space.exclusiveCalls.contains(11))
        XCTAssertTrue(space.attached.contains(11),
                      "the known-visible add-only membership remains the fallback")
        XCTAssertTrue(model.lockNotchMounted)
        coordinator.stop()
    }

    func testOverlayUsesExclusiveMigrationAndReportsRealBranch() async {
        space.exclusiveResult = ["ok": false, "reason": "membership-not-exclusive"]
        sessionLocked = true
        let coordinator = makeCoordinator()
        coordinator.setEnabled(true)
        events.deliverLocked(true)
        await drain()
        XCTAssertFalse(model.lockOverlayReady)
        XCTAssertTrue(space.exclusiveCalls.contains(724),
                      "the overlay attempts the owned-Space-only mount, including empty membership")
        XCTAssertTrue(model.lockNotchMounted, "primary stays visible when the overlay is refused")
        coordinator.stop()
    }

    func testUnrelatedPreferenceChangeDoesNotResetDeadlineGeneration() async {
        sessionLocked = true
        model.playing = false
        let coordinator = makeCoordinator()
        coordinator.setEnabled(true)
        await drain()
        let deadlineBefore = scheduler.tasks.filter { $0.delay == 600 }.count
        defaults.set(["enableLockScreen": true,
                      "allowNowPlayingWidgetWhenLocked": true,
                      "allowConnectivityWidgetWhenLocked": false,
                      "playSoundOnLock": false,
                      "playSoundOnUnlock": false,
                      "hoverDelay": 0.5], forKey: "referenceSettingsUI")
        settings.reloadPreferences()
        await drain()
        XCTAssertEqual(scheduler.tasks.filter { $0.delay == 600 }.count, deadlineBefore,
                       "unrelated settings must not create a fresh deadline")
        coordinator.stop()
    }
}
