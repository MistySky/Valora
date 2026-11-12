import Foundation
import XCTest
@testable import Valora
@testable import ReferenceCore

final class SystemMediaStreamAutoreleaseTests: XCTestCase {
    private func event(title: String, artwork: String? = nil) -> Data {
        var payload: [String: Any] = [
            "bundleIdentifier": "com.example.player",
            "title": title,
            "artist": "artist",
            "album": "album",
            "playing": true,
            "durationMicros": 240_000_000,
            "elapsedTimeMicros": 1_000_000,
            "playbackRate": 1
        ]
        if let artwork { payload["artworkData"] = artwork }
        let event: [String: Any] = ["type": "data", "diff": false, "payload": payload]
        return (try! JSONSerialization.data(withJSONObject: event)) + Data([10])
    }

    private func malformed() -> Data { Data("{not-json}\n".utf8) }
    private func nonData() -> Data {
        (try! JSONSerialization.data(withJSONObject: ["type": "error", "diff": false])) + Data([10])
    }
    private func diffLine() -> Data {
        (try! JSONSerialization.data(withJSONObject: ["type": "data", "diff": true,
                                                      "payload": ["title": "ignored"]])) + Data([10])
    }

    func testChunkBoundariesAndLineOrderArePreserved() {
        let first = event(title: "first")
        let second = event(title: "second")
        let split = first.count / 2
        let chunks = [
            first.prefix(split),
            Data(first[split...]) + second + malformed() + nonData() + diffLine(),
            Data()
        ]
        var index = 0
        var snapshots: [SystemMediaSnapshot?] = []
        let end = SystemMediaSource.readStream(readChunk: {
            defer { index += 1 }
            return chunks[index]
        }, emit: { snapshots.append($0) })
        XCTAssertEqual(end, .eof)
        XCTAssertEqual(index, 3)
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots.compactMap { $0?.title }, ["first", "second"])
        XCTAssertEqual(snapshots.compactMap { $0?.artwork }.count, 0)
    }

    func testInvalidPayloadEmitsNilInOrderAndArtworkIsOwned() {
        let valid = event(title: "valid", artwork: Data("cover".utf8).base64EncodedString())
        let invalidPayload = (try! JSONSerialization.data(withJSONObject: [
            "type": "data", "diff": false, "payload": ["title": "no bundle"]
        ])) + Data([10])
        var reads = 0
        var snapshots: [SystemMediaSnapshot?] = []
        let end = SystemMediaSource.readStream(readChunk: {
            defer { reads += 1 }
            return reads == 0 ? valid + invalidPayload : Data()
        }, emit: { snapshots.append($0) })
        XCTAssertEqual(end, .eof)
        XCTAssertEqual(snapshots.count, 2)
        XCTAssertEqual(snapshots[0]?.title, "valid")
        XCTAssertEqual(snapshots[0]?.artwork, Data("cover".utf8))
        XCTAssertNil(snapshots[1])
    }

    func testLimitStopsBeforeParsingAndKeepsOriginalBoundary() {
        var reads = 0
        var exceeded = 0
        var emitted: [SystemMediaSnapshot?] = []
        let chunk = Data(repeating: 0x7b, count: 64) + event(title: "too-late")
        let end = SystemMediaSource.readStream(readChunk: {
            defer { reads += 1 }
            return reads == 0 ? chunk : Data()
        }, bufferLimit: 32, didExceedLimit: {
            exceeded += 1
        }, emit: {
            emitted.append($0)
        })
        XCTAssertEqual(end, .bufferLimit)
        XCTAssertEqual(reads, 1)
        XCTAssertEqual(exceeded, 1)
        XCTAssertTrue(emitted.isEmpty, "limit must terminate before parsing this chunk")
    }

    func testExactBufferLimitStillParsesBeforeEof() {
        let chunk = event(title: "exact-limit")
        var reads = 0
        var emitted: [SystemMediaSnapshot?] = []
        let end = SystemMediaSource.readStream(readChunk: {
            defer { reads += 1 }
            return reads == 0 ? chunk : Data()
        }, bufferLimit: chunk.count, didExceedLimit: {
            XCTFail("the original limit is strictly greater-than, not greater-or-equal")
        }, emit: { emitted.append($0) })
        XCTAssertEqual(end, .eof)
        XCTAssertEqual(reads, 2)
        XCTAssertEqual(emitted.count, 1)
        XCTAssertEqual(emitted[0]?.title, "exact-limit")
    }

    func testEofWithPartialLineDoesNotEmit() {
        var reads = 0
        var emitted: [SystemMediaSnapshot?] = []
        let end = SystemMediaSource.readStream(readChunk: {
            defer { reads += 1 }
            return reads == 0 ? event(title: "complete").dropLast(1) : Data()
        }, emit: { emitted.append($0) })
        XCTAssertEqual(end, .eof)
        XCTAssertTrue(emitted.isEmpty)
    }
}
