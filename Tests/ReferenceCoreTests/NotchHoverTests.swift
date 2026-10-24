import XCTest
@testable import ReferenceCore
final class NotchHoverTests: XCTestCase {
    func testElevationOnlyAppliesToCollapsedCutout() {
        XCTAssertEqual(NotchHoverMetrics.scale(inside:true,expanded:false),CGSize(width:1.075,height:1.15))
        for pair in [(false,false),(false,true),(true,true)] {
            XCTAssertEqual(NotchHoverMetrics.scale(inside:pair.0,expanded:pair.1),CGSize(width:1,height:1))
        }
    }
    func testEnlargedEdgeRemainsInInputEnvelope() {
        let size=CGSize(width:259,height:32), scale=NotchHoverMetrics.scale(inside:true,expanded:false)
        let edge=NotchHoverMetrics.localPoint(centeredX:138,topY:36,size:size,scale:scale)
        XCTAssertTrue(CGRect(origin:.zero,size:size).contains(edge))
        let outside=NotchHoverMetrics.localPoint(centeredX:150,topY:40,size:size,scale:scale)
        XCTAssertFalse(CGRect(origin:.zero,size:size).contains(outside))
        let top=NotchHoverMetrics.localPoint(centeredX:0,topY:0,size:size,scale:scale)
        XCTAssertEqual(top,CGPoint(x:129.5,y:0))
    }
}
