import Darwin
import Foundation
import XCTest
import ReferenceCore
@testable import Valora

private final class AutoreleasedStreamMarker: NSObject {}

final class IndependentMediaStreamPoolTests: XCTestCase {
    /// Raw C pointers avoid adding Swift ownership conventions to the runtime
    /// function. The explicit +1 is balanced by the surrounding pool's drain.
    private func markerSurvivesNextRead(
        run: (_ read: () -> Data) -> Void
    ) throws -> Bool {
        let handle = try XCTUnwrap(dlopen(nil, RTLD_NOW))
        defer { dlclose(handle) }
        typealias Autorelease = @convention(c) (UnsafeMutableRawPointer) -> UnsafeMutableRawPointer
        let function = try XCTUnwrap(dlsym(handle, "objc_autorelease"))
        let releaseLater = unsafeBitCast(function, to: Autorelease.self)
        weak var marker: AutoreleasedStreamMarker?
        var reads = 0
        var survived = false
        func createMarker() {
            let value = AutoreleasedStreamMarker()
            marker = value
            _ = releaseLater(Unmanaged.passRetained(value).toOpaque())
        }
        autoreleasepool {
            run {
                reads += 1
                if reads == 1 {
                    createMarker()
                    XCTAssertNotNil(marker, "fixture must really enqueue an autoreleased object")
                    return Data([123]) // incomplete line: no media callback
                }
                survived = marker != nil
                return Data()
            }
        }
        XCTAssertEqual(reads, 2)
        XCTAssertNil(marker)
        return survived
    }

    func testRealAutoreleasedObjectDrainsBeforeNextReadWithNegativeControl() throws {
        let legacy = try markerSurvivesNextRead { read in
            while !read().isEmpty {} // original permanent-task release boundary
        }
        XCTAssertTrue(legacy, "negative control must expose the original retention")
        let fixed = try markerSurvivesNextRead { read in
            let end = SystemMediaSource.readStream(readChunk: read, emit: { _ in XCTFail() })
            XCTAssertEqual(end, .eof)
        }
        XCTAssertFalse(fixed, "production loop must drain before the next blocking read")
    }

    func testSnapshotsDeliveredOnMainRemainCompleteAfterReaderPoolsDrain() async throws {
        let artwork = Data((0..<512).map { UInt8($0 % 251) })
        let title = "新歌🎵\n下一行"
        let object: [String: Any] = [
            "type": "data", "diff": false,
            "payload": ["bundleIdentifier": "test.fixture", "title": title,
                        "artworkData": artwork.base64EncodedString()]
        ]
        let valid = try JSONSerialization.data(withJSONObject: object) + Data([10])
        let invalid = Data("{\"type\":\"data\",\"diff\":false,\"payload\":{}}\n".utf8)
        let input = valid + invalid + valid
        let received: [SystemMediaSnapshot?] = await withCheckedContinuation { continuation in
            DispatchQueue.global().async {
                var reads = 0
                var callbacks: [@Sendable () -> SystemMediaSnapshot?] = []
                _ = SystemMediaSource.readStream(readChunk: {
                    defer { reads += 1 }
                    return reads == 0 ? input : Data()
                }, emit: { snapshot in callbacks.append { snapshot } })
                // All production per-read pools have drained before delivery.
                let delivery = callbacks
                DispatchQueue.main.async {
                    continuation.resume(returning: delivery.map { $0() })
                }
            }
        }
        XCTAssertEqual(received.count, 3)
        XCTAssertEqual(received[0]?.title, title)
        XCTAssertEqual(received[0]?.artwork, artwork)
        XCTAssertNil(received[1])
        XCTAssertEqual(received[2]?.title, title)
        XCTAssertEqual(received[2]?.artwork, artwork)
    }
}
