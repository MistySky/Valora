import XCTest
@testable import ReferenceCore

final class ConnectionAppearanceTests: XCTestCase {
    func testPhysicalAndFloatingGeometry() {
        XCTAssertEqual(ConnectionArtworkMetrics.movieSize(notch: true), 32)
        XCTAssertEqual(ConnectionArtworkMetrics.movieSize(notch: false), 28)
        XCTAssertEqual(ConnectionArtworkMetrics.movieOffset(notch: true), -0.5)
        XCTAssertEqual(ConnectionArtworkMetrics.symbolSize(notch: false), 13)
    }

    func testFixedPolicyAndAppearance() {
        let fixed = ConnectivityPreferences()
        XCTAssertTrue(fixed.uses3DModels)
        XCTAssertEqual(fixed.duration, 5)
        XCTAssertEqual(fixed.lowBatteryThreshold, 20)
        XCTAssertTrue(fixed.warnOnLowBattery)
        XCTAssertTrue(fixed.playSoundOnLowBattery)

        // Hidden legacy values must not override fixed policy.
        let legacy = ConnectivityPreferences(values: [
            "connectivityModel": "Symbols",
            "connectivityDuration": 1,
            "warnOnLowConnectBattery": false,
            "lowConnectBatteryThreshold": 30,
            "playSoundOnLowConnectBattery": false
        ])
        XCTAssertTrue(legacy.uses3DModels, "legacy appearance selection must not override automatic artwork")
        XCTAssertEqual(legacy.duration, 5)
        XCTAssertEqual(legacy.lowBatteryThreshold, 20)
        XCTAssertTrue(legacy.warnOnLowBattery)
        XCTAssertTrue(legacy.playSoundOnLowBattery)
    }

    func testReduceMotionForcesSymbolFallback() {
        XCTAssertTrue(ConnectionArtworkPolicy.usesMovie(appearance: true, reduceMotion: false))
        XCTAssertFalse(ConnectionArtworkPolicy.usesMovie(appearance: true, reduceMotion: true))
        XCTAssertFalse(ConnectionArtworkPolicy.usesMovie(appearance: false, reduceMotion: false))
    }

    func testGenerationsNoLongerCollapseToOneSymbol() {
        XCTAssertEqual(AirPodsModel.airPods3.symbol, "airpods.gen3")
        XCTAssertEqual(AirPodsModel.airPods4.symbol, "airpods.gen4")
        XCTAssertEqual(AirPodsModel.pro2.symbol, "airpods.pro")
        XCTAssertEqual(AirPodsModel.max2.symbol, "airpodsmax")
    }

    func testAirPodsMaxColorMappingAndUnknownFallback() {
        XCTAssertEqual(AirPodsMaxColor.identify(rawColorID: nil), .spaceGray)
        XCTAssertEqual(AirPodsMaxColor.identify(rawColorID: 2), .red)
        XCTAssertEqual(AirPodsMaxColor.identify(rawColorID: 3), .skyBlue)
        XCTAssertEqual(AirPodsMaxColor.identify(rawColorID: 100), .spaceGray)
    }
}
