import XCTest
@testable import ReferenceCore

final class SystemMediaSnapshotTests: XCTestCase {
    func testRevisionPrefersContentItemIdentifier() throws {
        let payload: [String: Any] = ["bundleIdentifier":"com.test.player","title":"Track","artist":"Artist",
            "contentItemIdentifier":"UUID-1","durationMicros":1_000_000,"elapsedTimeMicros":0]
        let snapshot = try XCTUnwrap(SystemMediaSnapshot(payload))
        XCTAssertEqual(snapshot.revisionIdentity, "com.test.player\u{0}UUID-1")
        let plain = try XCTUnwrap(SystemMediaSnapshot(["bundleIdentifier":"com.test.player","title":"Track","artist":"Artist"]))
        XCTAssertEqual(plain.revisionIdentity, plain.identity)
    }
}

