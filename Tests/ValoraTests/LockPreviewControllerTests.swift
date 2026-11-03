import AppKit
import ReferenceCore
import XCTest
@testable import Valora

@MainActor
final class LockPreviewControllerTests: XCTestCase {
    final class FakeTask: LockScheduledTask {
        let delay: TimeInterval
        var action: (@MainActor @Sendable () -> Void)?
        var cancelled = false
        var fired = false
        init(delay: TimeInterval, action: @escaping @MainActor @Sendable () -> Void) {
            self.delay = delay; self.action = action
        }
        func cancel() { cancelled = true; action = nil }
        func fire() { guard !cancelled, !fired else { return }; fired = true; action?() }
    }
    final class FakeScheduler: LockScheduling {
        var tasks: [FakeTask] = []
        func schedule(after seconds: TimeInterval,
                      _ action: @escaping @MainActor @Sendable () -> Void) -> any LockScheduledTask {
            let task = FakeTask(delay: seconds, action: action); tasks.append(task); return task
        }
        func fire(_ delay: TimeInterval) {
            tasks.first(where: { $0.delay == delay && !$0.cancelled && !$0.fired })?.fire()
        }
    }
    final class FakeGeometry: LockGeometryAnimating {
        var pending: [() -> Void] = []
        var commits = 0
        func animate(_ changes: @escaping @MainActor () -> Void,
                     completion: @escaping @MainActor () -> Void) {
            commits += 1; changes(); pending.append(completion)
        }
        func completeNext() { guard !pending.isEmpty else { return }; pending.removeFirst()() }
    }

    private var suite = ""
    private var defaults: UserDefaults!
    private var settings: RevivalSettings!
    private var model: AppModel!
    private var scheduler: FakeScheduler!
    private var geometry: FakeGeometry!
    private var controller: LockPreviewController!
    private var collapseCalled = false
    private var pendingCollapse: (() -> Void)?

    override func setUp() {
        super.setUp()
        suite = "com.wangqing.valora.preview.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suite)!
        defaults.removePersistentDomain(forName: suite)
        defaults.set(["enableLockScreen": true,
                      "allowNowPlayingWidgetWhenLocked": true,
                      "allowConnectivityWidgetWhenLocked": true],
                     forKey: "referenceSettingsUI")
        settings = RevivalSettings(defaults: defaults)
        model = AppModel(settings: settings)
        model.title = "Fixture"; model.artist = "Fixture"; model.playing = true
        scheduler = FakeScheduler(); geometry = FakeGeometry()
        controller = LockPreviewController(model, scheduler: scheduler, geometryAnimator: geometry)
        controller.start()
    }

    private func drain() async {
        await Task.yield()
        await Task.yield()
    }

    override func tearDown() {
        controller.stop()
        defaults.removePersistentDomain(forName: suite)
        super.tearDown()
    }

    func testPreviewWithNoMusicStartsFromBaseGeometryAndExpandsLock() async {
        model.title = "暂无播放"
        model.playing = false
        model.previewLockScreenEnabled = true
        await drain()
        XCTAssertEqual(model.previewLockIndicator.phase, .neutralizing)
        XCTAssertFalse(model.showsMusicActivity)
        XCTAssertEqual(model.visibleSize, model.notchGeometry.compact)
        geometry.completeNext()
        XCTAssertEqual(model.previewLockIndicator.phase, .locked)
        XCTAssertTrue(model.showsLockActivity)
        XCTAssertFalse(model.isSessionLocked)
    }

    func testExpandedMusicUsesExistingCollapseCompletionBeforeNeutralStage() async {
        controller.stop()
        controller = LockPreviewController(model, scheduler: scheduler, geometryAnimator: geometry) { [weak self] completion in
            self?.collapseCalled = true
            self?.pendingCollapse = completion
        }
        controller.start()
        model.previewLockScreenEnabled = true
        await drain()
        XCTAssertTrue(collapseCalled)
        XCTAssertEqual(model.previewLockIndicator.phase, .locking)
        XCTAssertTrue(model.previewLockPresentationActive)
        pendingCollapse?()
        XCTAssertEqual(model.previewLockIndicator.phase, .neutralizing)
        geometry.completeNext()
        XCTAssertEqual(model.previewLockIndicator.phase, .locked)
    }

    func testPreviewUsesSameLockStagesWithoutRealSessionOrBackend() async {
        model.previewLockScreenEnabled = true
        await drain()
        XCTAssertTrue(model.previewLockPresentationActive)
        XCTAssertFalse(model.isSessionLocked, "preview must not claim a real locked session")
        XCTAssertEqual(model.lockIndicator.phase, .hidden, "real indicator must remain untouched")
        XCTAssertEqual(model.previewLockIndicator.phase, .neutralizing)
        XCTAssertFalse(model.lockNotchMounted)
        geometry.completeNext()
        XCTAssertEqual(model.previewLockIndicator.phase, .locked)
        XCTAssertTrue(model.showsLockActivity)
        XCTAssertFalse(model.showsMusicActivity)
        XCTAssertEqual(model.visibleSize.width, PresentationMetrics.stationarySize(
            geometry: model.notchGeometry, simulated: settings.forceSimulatedNotch,
            liveActivity: .locked).width)
        XCTAssertFalse(model.isSessionLocked)
    }

    func testPreviewOffUnlocksAndRestoresLatestMusic() async {
        model.previewLockScreenEnabled = true
        await drain()
        geometry.completeNext()
        XCTAssertEqual(model.previewLockIndicator.phase, .locked)
        model.previewLockScreenEnabled = false
        await drain()
        XCTAssertEqual(model.previewLockIndicator.phase, .unlocking)
        XCTAssertTrue(model.previewLockPresentationActive)
        scheduler.fire(0.8)
        XCTAssertEqual(model.previewLockIndicator.phase, .restoring)
        XCTAssertFalse(model.isSessionLocked)
        geometry.completeNext()
        XCTAssertFalse(model.previewLockPresentationActive)
        XCTAssertEqual(model.previewLockIndicator.phase, .hidden)
        XCTAssertTrue(model.showsMusicActivity)
        XCTAssertFalse(model.showLockActivityForTesting)
    }

    func testUnlockKeepsOpenGlyphWidthThenNeutralThenMusicExpands() async {
        model.previewLockScreenEnabled = true
        await drain()
        geometry.completeNext()
        XCTAssertEqual(model.previewLockIndicator.phase, .locked)
        let lockedWidth = model.visibleSize.width
        XCTAssertGreaterThan(lockedWidth, model.notchGeometry.compact.width)

        model.previewLockScreenEnabled = false
        await drain()
        XCTAssertEqual(model.previewLockIndicator.phase, .unlocking)
        XCTAssertEqual(model.visibleSize.width, lockedWidth,
                       "open glyph must remain in place at the locked activity width")
        XCTAssertFalse(model.showsMusicActivity)

        scheduler.fire(0.8)
        XCTAssertEqual(model.previewLockIndicator.phase, .restoring)
        XCTAssertEqual(model.visibleSize, model.notchGeometry.compact,
                       "neutral base must be visible before restoring music")
        XCTAssertFalse(model.showsMusicActivity,
                       "music must not expand before the neutral animation completion")

        geometry.completeNext()
        XCTAssertTrue(model.showsMusicActivity)
        XCTAssertGreaterThan(model.visibleSize.width, model.notchGeometry.compact.width)
        XCTAssertEqual(model.visibleSize.width, PresentationMetrics.stationarySize(
            geometry: model.notchGeometry, simulated: settings.forceSimulatedNotch,
            liveActivity: .playing).width)
    }

    func testUnlockWithoutMusicEndsAtNeutralBase() async {
        model.title = "暂无播放"
        model.playing = false
        model.previewLockScreenEnabled = true
        await drain()
        geometry.completeNext()
        model.previewLockScreenEnabled = false
        await drain()
        scheduler.fire(0.8)
        XCTAssertEqual(model.previewLockIndicator.phase, .restoring)
        geometry.completeNext()
        XCTAssertEqual(model.previewLockIndicator.phase, .hidden)
        XCTAssertFalse(model.showsMusicActivity)
        XCTAssertEqual(model.visibleSize, model.notchGeometry.compact)
    }

    func testRealLockCancelsPreviewWithoutChangingRealLockState() async {
        model.previewLockScreenEnabled = true
        await drain()
        geometry.completeNext()
        model.isSessionLocked = true
        await Task.yield(); await Task.yield()
        XCTAssertFalse(model.previewLockScreenEnabled)
        XCTAssertFalse(model.previewLockPresentationActive)
        XCTAssertTrue(model.isSessionLocked, "real lock state is owned by the real coordinator")
        XCTAssertEqual(model.previewLockIndicator.phase, .hidden)
    }

    func testRapidOnOffOnRejectsOldGeometryCompletion() async {
        model.previewLockScreenEnabled = true
        await drain()
        XCTAssertEqual(model.previewLockIndicator.phase, .neutralizing)
        model.previewLockScreenEnabled = false
        await drain()
        model.previewLockScreenEnabled = true
        await drain()
        XCTAssertTrue(model.previewLockPresentationActive)
        let oldPending = geometry.pending.count
        XCTAssertGreaterThanOrEqual(oldPending, 1)
        // The old completion must not move the new generation back to hidden.
        geometry.completeNext()
        XCTAssertTrue(model.previewLockPresentationActive)
        XCTAssertTrue(model.previewLockIndicator.phase == .neutralizing
                      || model.previewLockIndicator.phase == .locked)
    }

    func testMasterOffCancelsPreviewWithoutChangingRealSession() async {
        model.previewLockScreenEnabled = true
        await drain()
        geometry.completeNext()
        defaults.set(["enableLockScreen": false], forKey: "referenceSettingsUI")
        settings.reloadPreferences()
        await Task.yield(); await Task.yield()
        XCTAssertFalse(model.previewLockScreenEnabled)
        XCTAssertFalse(model.previewLockPresentationActive)
        XCTAssertFalse(model.isSessionLocked)
    }
}

private extension AppModel {
    var showLockActivityForTesting: Bool {
        previewLockPresentationActive && previewLockIndicator.showsBadge
    }
}
