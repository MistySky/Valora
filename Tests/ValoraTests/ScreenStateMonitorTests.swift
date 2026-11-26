import AppKit
import XCTest
@testable import Valora

@MainActor
final class ScreenStateMonitorTests: XCTestCase {
    private let display = CGRect(x: 0, y: 0, width: 1000, height: 500)
    private let dock = "com.apple.dock"
    private let windowManager = "com.apple.WindowManager"

    private func window(_ id: Int, pid: Int = 40, layer: Int = 0, owner: String = "App",
                        rect: CGRect? = nil) -> [String: Any] {
        let frame = rect ?? display
        return [kCGWindowNumber as String: id, kCGWindowOwnerPID as String: pid,
                kCGWindowOwnerName as String: owner, kCGWindowLayer as String: layer,
                kCGWindowBounds as String: ["X": frame.minX, "Y": frame.minY,
                                            "Width": frame.width, "Height": frame.height]]
    }

    func testOrdinaryWindowsAndNamesRejectWithoutProcessLookup() {
        let windows = [
            window(1, pid: 7), window(2, owner: "Window Server"), window(3, owner: "WindowManager"),
            window(4, rect: CGRect(x: 0, y: 0, width: 899, height: 500)),
            window(5, layer: 8), window(6, layer: 10, rect: CGRect(x: 0, y: 0, width: 997, height: 500)),
            window(7), [:]
        ]
        var spaceQueries: [Int] = []
        let state = ScreenStateMonitor.evaluate(windows: windows, displays: [display], ourPID: 7,
                                                processIdentifier: { _ in XCTFail("unexpected process lookup"); return nil },
                                                spaceTypes: { spaceQueries.append($0); return [0] })
        XCTAssertFalse(state.fullscreen)
        XCTAssertFalse(state.missionControl)
        XCTAssertEqual(spaceQueries, [7])
    }

    func testFullscreenSpaceIntersectionAndDisplaySizeFallback() {
        let cases: [(CGRect, [Int32], Bool)] = [
            (CGRect(x: 100, y: 100, width: 900, height: 400), [0, 4], true),
            (CGRect(x: 101, y: 100, width: 900, height: 400), [4], false),
            (CGRect(x: 100, y: 101, width: 900, height: 400), [4], false),
            (CGRect(x: 0, y: 0, width: 1002, height: 498), [], true),
            (CGRect(x: 0, y: 0, width: 1003, height: 500), [], false),
            (display, [0], false)
        ]
        for (rect, types, expected) in cases {
            let state = ScreenStateMonitor.evaluate(windows: [window(1, owner: "Dock", rect: rect)],
                                                    displays: [display], ourPID: 7,
                                                    processIdentifier: { _ in nil }, spaceTypes: { _ in types })
            XCTAssertEqual(state.fullscreen, expected)
            XCTAssertFalse(state.missionControl)
        }
    }

    func testSystemProcessesExcludedAndSharedLookupExpiresAfterEachSnapshot() {
        let windows = [
            window(1, pid: 10), window(2, pid: 20),
            window(3, pid: 99, layer: 10), window(4, pid: 20, layer: 11)
        ]
        var processes = [dock: 10, windowManager: 20]
        var calls: [String: Int] = [:]
        func evaluate() -> (fullscreen: Bool, missionControl: Bool) {
            ScreenStateMonitor.evaluate(windows: windows, displays: [display], ourPID: 7,
                                        processIdentifier: { calls[$0, default: 0] += 1; return processes[$0] },
                                        spaceTypes: { _ in [4] })
        }
        let first = evaluate()
        XCTAssertFalse(first.fullscreen)
        XCTAssertTrue(first.missionControl)
        XCTAssertEqual(calls, [dock: 1, windowManager: 1])

        processes = [dock: 11]
        let second = evaluate()
        XCTAssertTrue(second.fullscreen)
        XCTAssertFalse(second.missionControl)
        XCTAssertEqual(calls, [dock: 2, windowManager: 2])
    }

    func testMissionControlOnlyResolvesWindowManagerForMatchingUpperLayer() {
        let outsideDisplay = CGRect(x: 2500, y: 0, width: 998, height: 502)
        let windows = [window(1, pid: 51, layer: 10, owner: "WindowManager", rect: outsideDisplay),
                       window(2, pid: 50, layer: 10, owner: "Other", rect: outsideDisplay)]
        var calls: [String] = []
        let state = ScreenStateMonitor.evaluate(windows: windows, displays: [display], ourPID: 7,
                                                processIdentifier: { calls.append($0); return 50 },
                                                spaceTypes: { _ in XCTFail("unexpected Space lookup"); return [] })
        XCTAssertFalse(state.fullscreen)
        XCTAssertTrue(state.missionControl)
        XCTAssertEqual(calls, [windowManager])
    }
}
