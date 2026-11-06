import Foundation
import XCTest
@testable import Valora

@MainActor
final class IndependentHolidayDispatchTests: XCTestCase {
    func testHidingBeforeQueuedHolidayReadPreventsTransportCall() async {
        let transport = FixtureHolidayTransport(calendars: [
            HolidayCalendarDescriptor(id: "qa-holiday", title: "中国节假日",
                                      sourceTitle: "Fixture", isReadOnly: true)
        ], records: [])
        let provider = HolidayProvider(authorizationCheck: { true }, transportFactory: { transport })
        provider.start()
        provider.setPanelVisible(true)
        let start = Date(timeIntervalSince1970: 1_790_784_000)
        provider.ensureEvents(range: DateInterval(start: start, duration: 31 * 86_400))
        provider.setPanelVisible(false)
        for _ in 0..<30 { await Task.yield() }
        XCTAssertEqual(transport.eventReadCount, 0,
                       "queued work must recheck panel/feature lifetime before invoking the transport")
        provider.stop()
    }
}
