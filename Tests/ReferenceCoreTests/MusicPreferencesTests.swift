import XCTest
@testable import ReferenceCore

final class MusicPreferencesTests: XCTestCase {
    func testDefaultsAndDictionaryRoundTrip() throws {
        let original: [String: Any] = ["disableWaveform": true, "hideWhileSourceIsActive": true,
            "enableQuickPeek": false, "whenSongChanges": false, "peekDuration": 4.5]
        let data = try PropertyListSerialization.data(fromPropertyList: original, format: .binary, options: 0)
        let restored = try XCTUnwrap(PropertyListSerialization.propertyList(from:data,format:nil) as? [String:Any])
        let options = MusicPreferences(values: restored)
        XCTAssertTrue(options.disableWaveform)
        XCTAssertTrue(options.hideWhileSourceIsActive)
        XCTAssertFalse(options.quickPeekEnabled)
        XCTAssertFalse(options.whenSongChanges)
        XCTAssertEqual(options.peekDuration, 4.5)
        XCTAssertEqual(MusicPreferences().peekDuration, 2)
    }
    func testOnlyTheKnownCurrentSourceHidesActivity() {
        let options = MusicPreferences(values:["hideWhileSourceIsActive":true])
        XCTAssertTrue(options.hidesActivity(source:"com.tencent.QQMusicMac",frontmost:"com.tencent.QQMusicMac"))
        XCTAssertFalse(options.hidesActivity(source:"com.tencent.QQMusicMac",frontmost:"com.apple.finder"))
        XCTAssertFalse(options.hidesActivity(source:"",frontmost:""))
        XCTAssertFalse(MusicPreferences().hidesActivity(source:"player",frontmost:"player"))
    }
    func testLockScreenLyricsDefaultAndMasterComposition() {
        let defaults = MusicPreferences()
        XCTAssertFalse(defaults.lockScreenLyrics)
        XCTAssertFalse(defaults.showsLockScreenLyrics)
        let lockOnly = MusicPreferences(values: ["lockScreenLyrics": true])
        XCTAssertTrue(lockOnly.lockScreenLyrics)
        XCTAssertFalse(lockOnly.showsLockScreenLyrics,
                       "the master lyrics switch must govern the lock-specific choice")
        let both = MusicPreferences(values: ["showLyrics": true, "lockScreenLyrics": true])
        XCTAssertTrue(both.showsLockScreenLyrics)
        let masterOff = MusicPreferences(values: ["showLyrics": false, "lockScreenLyrics": true])
        XCTAssertFalse(masterOff.showsLockScreenLyrics)
    }

    func testDurationCannotCrashTaskSleepOrEscapeSliderBounds() {
        for invalid in [Double.nan, .infinity, -.infinity] {
            XCTAssertEqual(MusicPreferences(values:["peekDuration":invalid]).peekDuration, 2)
        }
        XCTAssertEqual(MusicPreferences(values:["peekDuration":0]).peekDuration, 1)
        XCTAssertEqual(MusicPreferences(values:["peekDuration":10]).peekDuration, 5)
    }
}
