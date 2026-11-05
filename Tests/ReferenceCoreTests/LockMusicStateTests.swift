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
    }

    /// The desktop simulation is a visible switch; it defaults off and never
    /// turns itself on from an archived dictionary.
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

/// V0088/V0089: the lock card's top edge and the host window are fixed across
/// the four expansion states; only the bottom edge moves. The anchor is chosen
/// from the fully expanded height so the card never enters the login-safe area.
/// Windowless arithmetic only — the offscreen AppKit card test covers the view
/// geometry; the real login window still has no public geometry.
final class LockCardLayoutTests: XCTestCase {
    private let layout = LockCardLayout(screenMinY: 0, screenHeight: 1117)

    func testFourStatesAddExactlyOneVolumeAndOneLyricsBlock() {
        let h = layout.cardHeight(volume: false, lyrics: false)
        let v = layout.cardHeight(volume: true, lyrics: false)
        let l = layout.cardHeight(volume: false, lyrics: true)
        let vl = layout.cardHeight(volume: true, lyrics: true)

        XCTAssertEqual(h, LockCardLayout.playerHeight, accuracy: 0.001)
        XCTAssertEqual(v - h, LockCardLayout.volumeBlock, accuracy: 0.001)
        XCTAssertEqual(l - h, LockCardLayout.lyricBlock, accuracy: 0.001)
        XCTAssertEqual(vl, v + l - h, accuracy: 0.001)
    }

    func testTopAndPanelOriginDoNotDependOnExpansion() {
        let origins = [(false, false), (true, false), (false, true), (true, true)].map { _ in
            layout.panelOriginY
        }
        XCTAssertEqual(Set(origins).count, 1, "the host origin must not change with the card height")
        // Bottom edge = top - height; it is the only moving edge.
        for (volume, lyrics) in [(false, false), (true, false), (false, true), (true, true)] {
            let bottom = layout.cardTop - layout.cardHeight(volume: volume, lyrics: lyrics)
            XCTAssertLessThan(bottom, layout.cardTop)
        }
    }

    /// V0091: the accepted card sat with its *bottom* on the 21% line. The fixed
    /// top is derived from that collapsed height, not from a reserved expanded
    /// block, so the player is not lifted.
    func testVolumeExpansionLandsOnTheReferenceLine() {
        // Collapsed card is lifted by exactly one volume block, so opening the
        // volume row puts its bottom back on the original 21% line.
        let collapsedBottom = layout.cardTop - LockCardLayout.playerHeight
        XCTAssertEqual(collapsedBottom, 1117 * 0.21 + LockCardLayout.volumeBlock, accuracy: 0.001)
        let volumeBottom = layout.cardTop - layout.cardHeight(volume: true, lyrics: false)
        XCTAssertEqual(volumeBottom, 1117 * 0.21, accuracy: 0.001)
        XCTAssertEqual(layout.panelOriginY, layout.cardTop - LockCardLayout.canvasHeight, accuracy: 0.001)
    }

    /// Reported trade-off, not compensated: expanding pushes the bottom below
    /// the 21% reference line by the reserved block height.
    func testExpandedCardExtendsBelowTheReferenceLine() {
        let below = LockCardLayout.lyricBlock
        XCTAssertEqual(layout.fullyExpandedBottom, 1117 * 0.21 - below, accuracy: 0.001)
        XCTAssertGreaterThan(below, 0)
    }

    func testEveryStateStaysAboveTheExpandedBottom() {
        for (volume, lyrics) in [(false, false), (true, false), (false, true), (true, true)] {
            let bottom = layout.cardTop - layout.cardHeight(volume: volume, lyrics: lyrics)
            XCTAssertGreaterThanOrEqual(bottom, layout.fullyExpandedBottom - 0.001,
                                        "state v=\(volume) l=\(lyrics) entered the reserved login gap")
        }
        let bottoms = [(false, false), (true, false), (false, true), (true, true)].map {
            layout.cardTop - layout.cardHeight(volume: $0.0, lyrics: $0.1)
        }
        XCTAssertEqual(Set(bottoms).count, 4, "four states must have four different bottom edges")
    }

    func testHostWindowSpansOnlyTheReservedCardRegion() {
        // No invisible host area below the login-safe line, where it could
        // intercept clicks intended for the login user/password controls.
        XCTAssertEqual(layout.fullyExpandedBottom,
                       layout.loginSafeBottom - LockCardLayout.lyricBlock,
                       accuracy: 0.001,
                       "only the lyric block still extends below the 21% line")
        XCTAssertEqual(layout.panelOriginY + LockCardLayout.canvasHeight, layout.cardTop, accuracy: 0.001)
    }

    func testShortScreenConflictIsReportedInsteadOfSilentlyShrinking() {
        // Anchored from the collapsed card, the top only needs to fit on screen;
        // the expanded bottom is allowed to run low and is reported separately.
        let short = LockCardLayout(screenMinY: 0, screenHeight: 200)
        XCTAssertFalse(short.fitsScreen)
        let justEnough = LockCardLayout(screenMinY: 0, screenHeight: 800)
        XCTAssertTrue(justEnough.fitsScreen)
    }

    func testTallestStateStillFitsTheHostWindow() {
        XCTAssertLessThanOrEqual(
            layout.cardHeight(volume: true, lyrics: true),
            LockCardLayout.canvasHeight,
            "the fixed host window must be tall enough for the fully expanded card"
        )
    }

    func testVerticalOffsetShiftsTopAndOriginTogether() {
        let shifted = LockCardLayout(screenMinY: 0, screenHeight: 1117, verticalOffset: 40)
        XCTAssertEqual(shifted.cardTop - layout.cardTop, 40, accuracy: 0.001)
        XCTAssertEqual(shifted.panelOriginY - layout.panelOriginY, 40, accuracy: 0.001)
    }

    /// V0096: on an external/clamshell target the fully expanded card must stay
    /// above the login line, so opening volume + lyrics cannot cover the avatar.
    func testExternalScreenReservesTheFullyExpandedCard() {
        let external = LockCardLayout(screenMinY: 0, screenHeight: 1080,
                                      reserveFullExpansion: true)
        // V0096-R3: external keeps the wiring but restores the 21% reference.
        XCTAssertEqual(external.reservedBottom, 1080 * 0.21, accuracy: 0.001)
        XCTAssertEqual(external.cardTop, 226.8 + LockCardLayout.maxCardHeight, accuracy: 0.001)
        XCTAssertEqual(external.cardTop - external.cardHeight(volume: false, lyrics: true),
                       258.8, accuracy: 0.001, "normal lyric state bottom")
        XCTAssertEqual(external.cardTop - LockCardLayout.maxCardHeight, 226.8, accuracy: 0.001)
        let expandedBottom = external.cardTop - LockCardLayout.maxCardHeight
        XCTAssertGreaterThanOrEqual(expandedBottom, external.loginSafeBottom - 0.001,
                                    "expanded card must not cross the login line")
        for (volume, lyrics) in [(false, false), (true, false), (false, true), (true, true)] {
            let bottom = external.cardTop - external.cardHeight(volume: volume, lyrics: lyrics)
            XCTAssertGreaterThanOrEqual(bottom, external.loginSafeBottom - 0.001)
        }
        // Still a fixed top: the host origin does not depend on the state.
        XCTAssertEqual(external.panelOriginY, external.cardTop - LockCardLayout.canvasHeight,
                       accuracy: 0.001)
    }

    /// Negative origins and short displays: the anchor is computed from the
    /// target screen's own frame, never from a fixed pixel offset.
    func testNegativeOriginExternalScreenKeepsTheAnchorRelativeToItsOwnFrame() {
        let screenMinY: Double = 300
        let external = LockCardLayout(screenMinY: screenMinY, screenHeight: 1080,
                                      verticalOffset: 0, reserveFullExpansion: true)
        XCTAssertEqual(external.cardTop - screenMinY,
                       1080 * LockCardLayout.externalReserveFraction + LockCardLayout.maxCardHeight,
                       accuracy: 0.001)
        XCTAssertEqual(external.cardTop - screenMinY, 466.8, accuracy: 0.001)
        XCTAssertGreaterThanOrEqual(external.panelOriginY, screenMinY,
                                    "the host stays inside the target screen")
    }

    /// The built-in screen keeps its accepted 21% + volume-clearance anchor.
    func testBuiltInScreenKeepsTheAcceptedAnchor() {
        let builtIn = LockCardLayout(screenMinY: 0, screenHeight: 1117)
        XCTAssertEqual(builtIn.reservedBottom, 1117 * 0.21, accuracy: 0.001)
        XCTAssertEqual(builtIn.cardTop,
                       1117 * 0.21 + LockCardLayout.playerHeight + LockCardLayout.volumeClearance,
                       accuracy: 0.001)
    }

    /// Same rule with a negative-origin external display: every coordinate is
    /// relative to that screen's own frame, never a fixed pixel offset.
    func testExternalAnchorTranslatesWithANegativeOriginScreen() {
        let screenMinY: Double = 300
        let external = LockCardLayout(screenMinY: screenMinY, screenHeight: 1080,
                                      reserveFullExpansion: true)
        XCTAssertEqual(external.reservedBottom - screenMinY, 226.8, accuracy: 0.001)
        XCTAssertEqual(external.cardTop - screenMinY, 466.8, accuracy: 0.001)
    }
}
