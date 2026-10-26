import AppKit
import Darwin
import XCTest
@testable import Valora

@MainActor
final class SystemMonitorTests: XCTestCase {
    private func ticks(user: UInt64, system: UInt64, idle: UInt64, nice: UInt64 = 0) -> SystemMonitor.CPUTicks {
        .init(user: user, system: system, idle: idle, nice: nice)
    }

    func testCPUCalculationAndInvalidSamples() {
        let previous = ticks(user: 0, system: 0, idle: 0)
        XCTAssertEqual(SystemMonitor.cpuUsage(current: ticks(user: 0, system: 0, idle: 1000), previous: previous) ?? .nan, 0, accuracy: 0.0001)
        XCTAssertEqual(SystemMonitor.cpuUsage(current: ticks(user: 700, system: 300, idle: 0), previous: previous) ?? .nan, 100, accuracy: 0.0001)
        XCTAssertEqual(SystemMonitor.cpuUsage(current: ticks(user: 300, system: 200, idle: 500), previous: previous) ?? .nan, 50, accuracy: 0.0001)
        XCTAssertNil(SystemMonitor.cpuUsage(current: previous, previous: previous))
        XCTAssertNil(SystemMonitor.cpuUsage(current: ticks(user: 10, system: 0, idle: 10), previous: nil))
        let resetPrevious = ticks(user: 1_000_000, system: 1_000_000, idle: 1_000_000)
        let resetCurrent = ticks(user: 50, system: 50, idle: 100)
        XCTAssertNil(SystemMonitor.cpuBreakdown(current: resetCurrent, previous: resetPrevious, elapsed: 3, coreCount: 10))
        let mask = UInt64(UInt32.max)
        let wrapped = SystemMonitor.cpuUsage(current: ticks(user: 5, system: 0, idle: 10),
                                             previous: ticks(user: mask - 5, system: 0, idle: 0),
                                             elapsed: 3, coreCount: 10)
        XCTAssertEqual(wrapped ?? .nan, 11.0 / 21.0 * 100, accuracy: 0.0001)
    }

    private func vm(physical: UInt64 = 1_000, free: UInt64 = 100, speculative: UInt64 = 0,
                    external: UInt64 = 200, purgeable: UInt64 = 50, wired: UInt64 = 100,
                    compressor: UInt64 = 100, internalPages: UInt64 = 400) -> SystemMonitor.VMRaw {
        .init(pageSize: 16384, physical: physical, free: free, wired: wired,
              purgeable: purgeable, speculative: speculative, compressor: compressor,
              external: external, internalPages: internalPages)
    }

    func testMemorySnapshotFormulaAndRejections() {
        XCTAssertEqual(SystemMonitor.memorySnapshot(vm: vm())?.used, 700)
        XCTAssertEqual(SystemMonitor.memorySnapshot(vm: vm(speculative: 30))?.used, 730)
        XCTAssertNil(SystemMonitor.memorySnapshot(vm: vm(free: 10, speculative: 40)))
        XCTAssertNil(SystemMonitor.memorySnapshot(vm: vm(free: 2000, external: 500)))
        XCTAssertNil(SystemMonitor.memorySnapshot(vm: vm(purgeable: 50, internalPages: 10)))
        XCTAssertNil(SystemMonitor.memorySnapshot(vm: vm(physical: 0)))
    }

    func testMemoryAndDiskFormatting() {
        XCTAssertEqual(UIStyle.memoryString(0), "0 MB")
        XCTAssertEqual(UIStyle.memoryString(1_048_576), "1 MB")
        XCTAssertEqual(UIStyle.memoryString(1_500_000_000), "1.40 GB")
        XCTAssertEqual(UIStyle.memoryCapacityString(34_359_738_368), "32 GB")
        XCTAssertEqual(UIStyle.diskCapacityString(494_384_795_648), "494.4 GB")
        XCTAssertEqual(UIStyle.percentString(nil), "--%")
        XCTAssertEqual(UIStyle.percentString(0), "0%")
    }

    func testSearchAndProcessAggregation() {
        let apps = [
            AppMemoryReader.AppUsage(id: "1", name: "飞书", icon: nil, bytes: 1, processCount: 1, readableCount: 1, status: .ok),
            AppMemoryReader.AppUsage(id: "2", name: "微信", icon: nil, bytes: 1, processCount: 1, readableCount: 1, status: .ok)
        ]
        XCTAssertEqual(AppMemoryReader.filter(apps, query: "飞").map(\.name), ["飞书"])
        XCTAssertEqual(AppMemoryReader.filter(apps, query: "CHAT").count, 0)
        XCTAssertEqual(AppMemoryReader.rootBundle("/Applications/Lark.app/Contents/MacOS/Lark"), "/Applications/Lark.app")
        XCTAssertEqual(AppMemoryReader.rootBundle("/Applications/Lark.app/Contents/Frameworks/Lark Helper.app/Contents/MacOS/Lark Helper"), "/Applications/Lark.app")
    }

    func testMonitorLifecycleAndWakeBaseline() {
        let monitor = SystemMonitor()
        XCTAssertFalse(monitor.isRunning)
        monitor.start()
        XCTAssertTrue(monitor.isRunning)
        monitor.start()
        XCTAssertTrue(monitor.isRunning)
        monitor.setPanelVisible(true)
        monitor.setPanelVisible(false)
        XCTAssertTrue(monitor.applications.isEmpty)
        XCTAssertEqual(monitor.applicationState, .idle)
        monitor.handleWake()
        XCTAssertNil(monitor.snapshot.cpu.usage)
        monitor.stop()
        XCTAssertFalse(monitor.isRunning)
        XCTAssertNil(monitor.snapshot.disk)
        XCTAssertTrue(monitor.applications.isEmpty)
    }



    func testApplicationIconCacheIsBoundedAndTrimClearsIt() {
        let reader = AppMemoryReader()
        XCTAssertGreaterThan(AppMemoryReader.iconCacheLimit, 0)
        _ = reader.runningApplications()
        XCTAssertLessThanOrEqual(reader.iconCacheCount, AppMemoryReader.iconCacheLimit)
        reader.purge()
        XCTAssertEqual(reader.iconCacheCount, 0)
    }

    func testLiveReadsReturnPlausiblePublicValues() throws {
        let vm = try XCTUnwrap(SystemMonitor.readVMStatistics())
        XCTAssertGreaterThan(vm.physical, 0)
        let snapshot = try XCTUnwrap(SystemMonitor.memorySnapshot(vm: vm))
        XCTAssertLessThanOrEqual(snapshot.used, snapshot.total)
        XCTAssertNotNil(SystemMonitor.readCPUTicks())
        // Bounded single read only; no long-running background capture.
        if let disk = SystemMonitor.readDisk() {
            XCTAssertGreaterThan(disk.total, 0)
            XCTAssertLessThanOrEqual(disk.used, disk.total)
        }
    }

    func testStaleApplicationSampleAfterPanelCloseIsDiscarded() {
        let reader = GatedReader()
        let monitor = SystemMonitor(reader: reader)
        monitor.start()
        waitUntilIdle(monitor)
        reader.startGating()
        monitor.setPanelVisible(true)
        XCTAssertTrue(reader.waitUntilSampling())
        monitor.setPanelVisible(false)
        let trimsBefore = reader.trimCount
        reader.stopGating()
        reader.releaseSample()
        waitUntilIdle(monitor)
        XCTAssertTrue(monitor.applications.isEmpty)
        XCTAssertEqual(monitor.applicationState, .idle)
        XCTAssertGreaterThan(reader.trimCount, trimsBefore)
        XCTAssertFalse(reader.hasCachedSample)
        monitor.stop()
    }

    private func waitUntilIdle(_ monitor: SystemMonitor, timeout: TimeInterval = 3) {
        let deadline = Date().addingTimeInterval(timeout)
        while monitor.isSampling && Date() < deadline {
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
    }

    func testVerificationApplyDoesNotStartSampling() {
        let monitor = SystemMonitor()
        let snapshot = SystemMonitor.Snapshot(
            cpu: .init(usage: 23),
            memory: .init(total: 32 * 1_073_741_824, used: 20 * 1_073_741_824),
            disk: .init(volumePath: "/", volumeIdentifier: "x", total: 500_000_000_000,
                        available: 200_000_000_000, used: 300_000_000_000),
            device: .init(chip: "Preview", osVersion: "macOS 27"),
            uptime: "已运行 1 天")
        monitor.verificationApply(snapshot: snapshot)
        XCTAssertFalse(monitor.isRunning)
        XCTAssertEqual(monitor.snapshot.cpu.usage, 23)
        XCTAssertEqual(monitor.snapshot.memory?.usedPercent ?? 0, 62.5, accuracy: 0.001)
    }
}


/// Test double whose application sample blocks until released, controlling the
/// completion point without a timing guess.
final class GatedReader: AppMemoryReading {
    private let entered = DispatchSemaphore(value: 0)
    private let release = DispatchSemaphore(value: 0)
    private let lock = NSLock()
    private var gated = false
    private var trims = 0
    private var cached = false
    var trimCount: Int { lock.lock(); defer { lock.unlock() }; return trims }
    var hasCachedSample: Bool { lock.lock(); defer { lock.unlock() }; return cached }

    func runningApplications() -> [AppMemoryReader.AppDescriptor] {
        [AppMemoryReader.AppDescriptor(bundleIdentifier: "test.app", name: "TestApp",
                                      bundlePath: "/Applications/TestApp.app",
                                      rootPath: "/Applications/TestApp.app", icon: nil)]
    }

    func startGating() { lock.lock(); gated = true; lock.unlock() }
    func stopGating() { lock.lock(); gated = false; lock.unlock() }

    func sample(applications: [AppMemoryReader.AppDescriptor]) -> AppMemoryReader.SampleResult {
        lock.lock(); let shouldBlock = gated; lock.unlock()
        if shouldBlock {
            entered.signal()
            release.wait()
        }
        lock.lock(); cached = true; lock.unlock()
        let rows = applications.map {
            AppMemoryReader.AppUsage(id: $0.bundleIdentifier, name: $0.name, icon: nil,
                                     bytes: 42, processCount: 1, readableCount: 1, status: .ok)
        }
        return AppMemoryReader.SampleResult(rows: rows, state: .ready)
    }

    func waitUntilSampling(timeout: TimeInterval = 3) -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if entered.wait(timeout: .now() + 0.05) == .success { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.02))
        }
        return false
    }

    func releaseSample() { release.signal() }
    func purge() { lock.lock(); cached = false; lock.unlock() }
    func trimCache() { lock.lock(); trims += 1; cached = false; lock.unlock() }
}
