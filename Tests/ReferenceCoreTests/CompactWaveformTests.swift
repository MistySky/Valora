import XCTest
@testable import ReferenceCore

final class CompactWaveformTests: XCTestCase {
    func testRecoveredUnsignedHashVector() {
        // Independent unsigned 64-bit evaluation of 1003c5e44, height=12.
        XCTAssertEqual((0..<5).map { CompactWaveformMetrics.amplitude(bar:$0,tick:0,seed:0,revision:0) },[3,5,12,2,8])
    }
    func testSourceRevisionAndOverflowStayWithinRecoveredHeightRange() {
        let first=(0..<5).map { CompactWaveformMetrics.amplitude(bar:$0,tick:UInt64.max,seed:UInt64.max,revision:0) }
        let second=(0..<5).map { CompactWaveformMetrics.amplitude(bar:$0,tick:UInt64.max,seed:UInt64.max,revision:1) }
        XCTAssertNotEqual(first,second)
        XCTAssertTrue((first+second).allSatisfy { (2...12).contains($0) && $0.rounded() == $0 })
    }
    func testExpandedConstructorHasItsOwnEnvelope() {
        let profile=WaveformProfile.expanded
        XCTAssertEqual(profile.span,22)
        XCTAssertEqual(profile.side,24)
        XCTAssertEqual(profile.height,15)
        let heights=(0..<profile.count).map { CompactWaveformMetrics.amplitude(bar:$0,tick:0,seed:0,revision:0,maximumHeight:15) }
        XCTAssertEqual(heights.count,6)
        XCTAssertTrue(heights.allSatisfy { (2...15).contains($0) })
        XCTAssertEqual(CompactArtworkMetrics.side(notch:false),17-1.5)
        XCTAssertEqual(CompactArtworkMetrics.side(notch:true),20)
        XCTAssertEqual(CompactArtworkMetrics.corner(notch:true),5)
        XCTAssertEqual(CompactArtworkMetrics.corner(notch:true,elevated:true),5.5)
        XCTAssertEqual(CompactArtworkMetrics.corner(notch:false),4)
        XCTAssertEqual(CompactArtworkMetrics.corner(notch:false,elevated:true),4.5)
    }
}
