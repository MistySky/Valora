import XCTest
@testable import Valora
import ReferenceCore

@MainActor
final class MusicTitleExtrasIntegrationTests: XCTestCase {
    func testRemovedTitleExtrasSettingCannotOverrideFixedFullTitle() {
        let suite = "com.wangqing.valora.tests.title-extras.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        let settings = RevivalSettings(defaults: defaults)
        let model = AppModel(settings: settings)
        let draft = SettingsDraft(defaults: defaults)
        model.title = "Song (Live)"
        model.artist = "Artist [Band]"
        model.mediaRevisionIdentity = "original-media-id"
        XCTAssertEqual(model.displayTitle, "Song (Live)")

        // Legacy value is ignored; the fixed policy keeps the full title.
        draft.binding("hideSongTitleExtras", false).wrappedValue = true
        settings.reloadPreferences()
        XCTAssertEqual(model.displayTitle, "Song (Live)")
        XCTAssertEqual(model.title, "Song (Live)")
        XCTAssertEqual(model.artist, "Artist [Band]")
        XCTAssertEqual(model.mediaRevisionIdentity, "original-media-id")
        XCTAssertFalse(settings.musicPreferences.hideSongTitleExtras)

        let reloaded = AppModel(settings: RevivalSettings(defaults: defaults))
        reloaded.title = model.title
        XCTAssertEqual(reloaded.displayTitle, "Song (Live)")
    }
}
