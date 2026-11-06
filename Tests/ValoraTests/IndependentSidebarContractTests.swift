import XCTest
@testable import Valora

@MainActor
final class IndependentSidebarContractTests: XCTestCase {
    func testApprovedSidebarWithoutWindowCoordinatorSetup() {
        XCTAssertEqual(SettingsSidebar.groups.map(\.title), [nil, "刘海屏", "菜单栏", "Valora"])
        XCTAssertEqual(SettingsSidebar.groups.map { $0.pages.map(\.displayTitle) }, [
            ["通用"], ["音乐", "锁定屏幕", "设备连接"],
            ["日历", "系统监控", "Codex 用量"], ["关于"]
        ])
        XCTAssertEqual(SettingsPage.allCases.map(\.displayTitle),
                       ["通用", "音乐", "锁定屏幕", "设备连接",
                        "日历", "系统监控", "Codex 用量", "关于"])
        XCTAssertEqual(SettingsSidebar.orderedPages.count, Set(SettingsSidebar.orderedPages).count)
        XCTAssertEqual(SettingsPage.nowPlaying.symbol, "play.fill")
        XCTAssertEqual(SettingsLayout.titleContentGap, 13, accuracy: 0.001)
    }
}
