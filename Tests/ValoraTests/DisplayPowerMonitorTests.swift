import CoreGraphics
import XCTest
@testable import Valora

@MainActor
final class DisplayPowerMonitorTests: XCTestCase {
    private func allAsleep(_ states: [Bool], announcedCount: UInt32? = nil,
                           failingList: Bool = false) -> Bool {
        DisplayPowerMonitor.readDisplaySleep(online: { capacity, displays, count in
            guard let displays else {
                count?.pointee = announcedCount ?? UInt32(states.count)
                return .success
            }
            if failingList { return .failure }
            let copied = min(states.count, Int(capacity))
            for index in 0..<copied { displays[index] = UInt32(index) }
            count?.pointee = UInt32(copied)
            return .success
        }, isAsleep: { states[Int($0)] })
    }

    func testOnlyACompleteNonemptySnapshotOfSleepingDisplaysSuspendsRendering() {
        XCTAssertTrue(allAsleep([true]))
        XCTAssertTrue(allAsleep(Array(repeating: true, count: 17)))
        XCTAssertFalse(allAsleep([true, false, true]))
        XCTAssertFalse(allAsleep([]))
        XCTAssertFalse(allAsleep([], announcedCount: 2))
        XCTAssertFalse(allAsleep([true, true, false], announcedCount: 1))
        XCTAssertFalse(allAsleep([true], failingList: true))
        XCTAssertFalse(DisplayPowerMonitor.readDisplaySleep(online: { _, _, _ in .failure }))
    }

    func testHintsAndMissedNotificationsUseTheSameStateAndCancelCleanly() {
        var asleep = false
        var reads = 0
        var cancels = 0
        var hints: [DisplayPowerMonitor.ChangeHint] = []
        let monitor = DisplayPowerMonitor(readAllDisplaysAsleep: { reads += 1; return asleep },
                                          observeChanges: { hint in
            hints.append(hint)
            return { cancels += 1 }
        })
        var changes: [Bool] = []
        monitor.onChange = { changes.append($0) }
        monitor.refresh()
        XCTAssertEqual(reads, 0)
        monitor.start()
        monitor.start()
        XCTAssertEqual(hints.count, 1)

        asleep = true
        monitor.refresh()
        hints[0]()
        XCTAssertEqual(changes, [true])
        asleep = false
        hints[0]()
        XCTAssertEqual(changes, [true, false])

        asleep = true
        monitor.refresh()
        monitor.stop()
        XCTAssertFalse(monitor.allDisplaysAsleep)
        let stoppedReads = reads
        monitor.refresh()
        hints[0]()
        XCTAssertEqual(reads, stoppedReads)

        monitor.start()
        XCTAssertTrue(monitor.allDisplaysAsleep)
        let restartedReads = reads
        hints[0]()
        XCTAssertEqual(reads, restartedReads)
        monitor.stop()
        XCTAssertEqual(cancels, 2)
    }
}
