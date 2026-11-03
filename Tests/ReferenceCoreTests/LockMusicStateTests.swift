import XCTest
import ReferenceCore

final class LockMusicStateTests: XCTestCase {
    private var preferences: LockMusicPreferences {
        LockMusicPreferences(values: ["enableLockScreen": true])
    }

    func testDefaultsPreserveSelectedLockPolicy() {
        let p = LockMusicPreferences()
        XCTAssertTrue(p.enabled)
        XCTAssertTrue(p.musicEnabled)
        XCTAssertFalse(p.soundOnLock)
        XCTAssertTrue(p.soundOnUnlock)
        XCTAssertEqual(p.idleSeconds, 600)
        XCTAssertFalse(p.showVolume)
        XCTAssertTrue(p.glass)
    }

    /// The lock page no longer owns a music switch: an archived lock-only
    /// preference must not veto the Now Playing module switch.
    func testArchivedLockOnlyPreferencesDoNotVetoModuleSwitches() {
        let archived = LockMusicPreferences(values: [
            "enableLockScreen": true,
            "allowNowPlayingWidgetWhenLocked": false,
            "allowConnectivityWidgetWhenLocked": false])
        XCTAssertTrue(archived.enabled)
        XCTAssertTrue(archived.musicEnabled,
                      "the lock-only music preference is no longer read")
    }

    func testPhysicalLockActivityUsesSameCompactGeometryAsPlayingMusic() {
        let geometry = NotchGeometry.calculate(screenWidth: 1728, safeAreaTop: 32,
            auxiliaryLeftWidth: 771.5, auxiliaryRightWidth: 771.5,
            menuBarHeight: 32, simulated: false)
        let playing = PresentationMetrics.stationarySize(geometry: geometry, simulated: false,
            liveActivity: .playing)
        let locked = PresentationMetrics.stationarySize(geometry: geometry, simulated: false,
            liveActivity: .locked)
        XCTAssertEqual(locked, playing,
                       "physical lock activity must be the same compact width/height as music; only the wing content changes")
        XCTAssertEqual(locked.height, geometry.compact.height)
        XCTAssertGreaterThan(locked.width, geometry.compact.width)
    }

    func testLegacyIdleAndOffsetValuesCannotOverrideFixedPolicy() {
        let p = LockMusicPreferences(values: ["hideIdleDuration": 1, "nowPlayingWidgetOffset": 31])
        XCTAssertEqual(p.idleSeconds, 600)
        XCTAssertEqual(p.offset, 0)
    }

    func testLockedPlayingShowsPanelAndRapidStateChangesAdvanceGeneration() {
        var state = LockMusicState()
        state.update(locked: true, sleeping: false, hasTrack: true, playing: true,
                     identity: "a", preferences: preferences, now: 10)
        XCTAssertTrue(state.visible)
        XCTAssertNil(state.deadline)
        let first = state.generation
        state.update(locked: false, sleeping: false, hasTrack: true, playing: true,
                     identity: "a", preferences: preferences, now: 11)
        XCTAssertFalse(state.visible)
        XCTAssertGreaterThan(state.generation, first)
        state.update(locked: true, sleeping: false, hasTrack: true, playing: true,
                     identity: "a", preferences: preferences, now: 12)
        XCTAssertTrue(state.visible)
        XCTAssertGreaterThan(state.generation, first + 1)
    }

    func testNoSoundAndNoPanelWhenStartupIsAlreadyLockedIsHandledByBaselineFlag() {
        // The coordinator seeds lastLocked from the session before taking an
        // edge; this state test proves no visibility is inferred solely from
        // a missing media item.
        var state = LockMusicState()
        state.update(locked: true, sleeping: false, hasTrack: false, playing: false,
                     identity: "", preferences: preferences, now: 0)
        XCTAssertFalse(state.visible)
    }

    func testSleepHidesAndWakeReevaluates() {
        var state = LockMusicState()
        state.update(locked: true, sleeping: false, hasTrack: true, playing: true,
                     identity: "a", preferences: preferences, now: 0)
        XCTAssertTrue(state.visible)
        state.update(locked: true, sleeping: true, hasTrack: true, playing: true,
                     identity: "a", preferences: preferences, now: 1)
        XCTAssertFalse(state.visible)
        state.update(locked: true, sleeping: false, hasTrack: true, playing: true,
                     identity: "a", preferences: preferences, now: 2)
        XCTAssertTrue(state.visible)
    }

    func testPausedIdleDeadlineIsTenMinutesAndExpiresOnlyMatchingGeneration() {
        var state = LockMusicState()
        state.update(locked: true, sleeping: false, hasTrack: true, playing: false,
                     identity: "a", preferences: preferences, now: 100)
        let token = state.generation
        XCTAssertEqual(state.deadline, 700)
        state.expire(token: token, now: 699.9)
        XCTAssertTrue(state.visible)
        state.update(locked: true, sleeping: false, hasTrack: true, playing: true,
                     identity: "a", preferences: preferences, now: 700)
        state.expire(token: token, now: 800)
        XCTAssertTrue(state.visible, "a stale deadline must not hide a resumed track")
        state.update(locked: true, sleeping: false, hasTrack: true, playing: false,
                     identity: "a", preferences: preferences, now: 800)
        let resumedToken = state.generation
        state.expire(token: resumedToken, now: 1400)
        XCTAssertFalse(state.visible)
    }

    func testMusicAndMasterSwitchesAreIndependentAndOffHides() {
        var state = LockMusicState()
        var p = preferences
        p.musicEnabled = false
        state.update(locked: true, sleeping: false, hasTrack: true, playing: true,
                     identity: "a", preferences: p, now: 0)
        XCTAssertFalse(state.visible)
        p.musicEnabled = true
        state.update(locked: true, sleeping: false, hasTrack: true, playing: true,
                     identity: "a", preferences: p, now: 1)
        XCTAssertTrue(state.visible)
        p.enabled = false
        state.update(locked: true, sleeping: false, hasTrack: true, playing: true,
                     identity: "a", preferences: p, now: 2)
        XCTAssertFalse(state.visible)
    }

    func testLockIndicatorStagedOrderAndStaleCompletion() {
        var indicator = LockIndicatorState()
        let lockToken = indicator.beginLocking()
        XCTAssertEqual(indicator.phase, .locking)
        XCTAssertFalse(indicator.showsBadge)
        XCTAssertTrue(indicator.isLocking)
        XCTAssertTrue(indicator.completeLocking(token: lockToken))
        XCTAssertEqual(indicator.phase, .locked)
        XCTAssertTrue(indicator.showsBadge)

        let unlockToken = indicator.beginUnlocking()
        XCTAssertEqual(indicator.phase, .unlocking)
        XCTAssertTrue(indicator.showsBadge)
        XCTAssertTrue(indicator.finishUnlockToRestoring(token: unlockToken))
        XCTAssertEqual(indicator.phase, .restoring)
        XCTAssertFalse(indicator.showsBadge)
        let restoreToken = indicator.generation
        XCTAssertTrue(indicator.finishRestoring(token: restoreToken))
        XCTAssertEqual(indicator.phase, .hidden)
        XCTAssertFalse(indicator.finishRestoring(token: restoreToken))
    }

    func testLockIndicatorNeutralGeometryStages() {
        var indicator = LockIndicatorState()
        let lockToken = indicator.beginLocking()
        XCTAssertEqual(indicator.phase, .locking)
        let neutralToken = indicator.beginNeutralizing()
        XCTAssertEqual(indicator.phase, .neutralizing)
        XCTAssertTrue(indicator.isNeutralGeometry)
        XCTAssertFalse(indicator.showsBadge)
        XCTAssertTrue(indicator.completeLocking(token: neutralToken))
        XCTAssertEqual(indicator.phase, .locked)
        let unlockToken = indicator.beginUnlocking()
        XCTAssertTrue(indicator.finishUnlockToRestoring(token: unlockToken))
        XCTAssertEqual(indicator.phase, .restoring)
        XCTAssertTrue(indicator.isNeutralGeometry)
        XCTAssertFalse(indicator.showsBadge)
        XCTAssertFalse(indicator.completeLocking(token: lockToken))
        XCTAssertEqual(indicator.phase, .restoring)
    }

    func testLockIndicatorRejectsOldLockAndUnlockTokens() {
        var indicator = LockIndicatorState()
        let oldLock = indicator.beginLocking()
        indicator.forceHidden()
        XCTAssertFalse(indicator.completeLocking(token: oldLock))
        XCTAssertEqual(indicator.phase, .hidden)
        indicator.forceLocked()
        let oldUnlock = indicator.beginUnlocking()
        indicator.forceLocked()
        XCTAssertFalse(indicator.finishUnlockToRestoring(token: oldUnlock))
        XCTAssertFalse(indicator.finishUnlockToRestoring(token: indicator.generation))
        XCTAssertEqual(indicator.phase, .locked)
    }

    func testLockIndicatorUnlockDelayUsesGenerationAndRejectsStaleToken() {
        var indicator = LockIndicatorState()
        indicator.update(locked: true, enabled: true, sleeping: false)
        XCTAssertEqual(indicator.phase, .locked)
        let lockedToken = indicator.generation
        indicator.update(locked: false, enabled: true, sleeping: false)
        XCTAssertEqual(indicator.phase, .unlocking)
        indicator.finishUnlock(token: lockedToken)
        XCTAssertEqual(indicator.phase, .unlocking, "stale completion must be ignored")
        let unlockToken = indicator.generation
        indicator.update(locked: true, enabled: true, sleeping: false)
        indicator.finishUnlock(token: unlockToken)
        XCTAssertEqual(indicator.phase, .locked)
        indicator.update(locked: true, enabled: false, sleeping: false)
        XCTAssertEqual(indicator.phase, .hidden)
    }
}
