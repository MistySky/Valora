import AppKit
import SwiftUI
import XCTest
@testable import Valora

@MainActor
final class IndependentDeviceBatteryPreviewTests: XCTestCase {
    func testRenderSummaryWithDevice() throws {
        let row = DeviceBatteryRowData(deviceID: "fixture", name: "AirPods 3", ears: "全部85%", caseText: "盒--%", accessibility: "fixture")
        let view = MonitorSummaryCard(snapshot: SystemMonitor.Snapshot(uptime: "已运行 2 天"), device: row)
        let renderer = ImageRenderer(content: view.frame(width: 400).background(Color.white))
        renderer.scale = 2
        let image = try XCTUnwrap(renderer.cgImage)
        let rep = NSBitmapImageRep(cgImage: image)
        try XCTUnwrap(rep.representation(using: .png, properties: [:])).write(to: URL(fileURLWithPath: "/private/tmp/valora-v0110-device-summary.png"))
    }
}
