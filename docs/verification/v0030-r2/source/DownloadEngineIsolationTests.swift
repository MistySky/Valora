import Foundation
import XCTest
import DownloadEngine
@testable import Valora

@MainActor
final class DownloadEngineIsolationTests: XCTestCase {
    func testIndependentAutomaticEnqueueCannotStartAfterFeatureOff() async throws {
        let root = root("independent-late-enqueue")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeSource(root, size: 2 * 1024 * 1024)
        let server = try startServer(file: source, root: root, slow: true)
        defer { server.stop() }
        let env = ValoraDownloadEnvironment.qa(root: root, suite: "valora.independent.late-enqueue.\(UUID().uuidString)")
        env.settings.autoStartDownloads = true
        let service = DownloadEngineService(environment: env)
        try await service.enqueue(source: server.baseURL.appendingPathComponent("source.bin"),
                                  destination: root.appendingPathComponent("downloads/late.bin"))
        await service.pauseAllAndSave()
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(service.items.first?.state, .paused,
                       "the engine's deferred automatic start must also obey feature off")
        XCTAssertEqual(service.manager.activeCount, 0)
        service.activate()
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(service.items.first?.state, .paused,
                       "fast off-on must not revive the deferred automatic start")
        XCTAssertEqual(service.manager.activeCount, 0)
        await service.pauseAllAndSave()
    }

    func testIndependentQueuedResumeCannotRestartAfterFeatureOff() async throws {
        let root = root("independent-late-resume")
        defer { try? FileManager.default.removeItem(at: root) }
        let source = try makeSource(root, size: 2 * 1024 * 1024)
        let server = try startServer(file: source, root: root, slow: true)
        defer { server.stop() }
        let env = ValoraDownloadEnvironment.qa(root: root, suite: "valora.independent.late-resume.\(UUID().uuidString)")
        env.settings.autoStartDownloads = false
        let service = DownloadEngineService(environment: env)
        try await service.enqueue(source: server.baseURL.appendingPathComponent("source.bin"),
                                  destination: root.appendingPathComponent("downloads/late.bin"))
        let id = try XCTUnwrap(service.items.first?.id)
        await service.pause(id: id)
        try await service.resume(id: id)
        // This is the real feature-off service path. A previously queued
        // action must not start network work after it has finished.
        await service.pauseAllAndSave()
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(service.items.first?.state, .paused)
        XCTAssertEqual(service.manager.activeCount, 0)
        service.activate()
        try await Task.sleep(for: .milliseconds(600))
        XCTAssertEqual(service.items.first?.state, .paused,
                       "fast off-on activation must not revive a queued old resume")
        XCTAssertEqual(service.manager.activeCount, 0)
        await service.pauseAllAndSave()
    }

    private struct Server {
        let process: Process
        let baseURL: URL
        func stop() { process.terminate(); process.waitUntilExit() }
    }

    private func startServer(file: URL, root: URL, slow: Bool = false) throws -> Server {
        let fixture = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .appendingPathComponent("Fixtures/range_http_server.py")
        let portFile = root.appendingPathComponent("port.txt")
        for attempt in 0..<3 {
            let portFile = root.appendingPathComponent("port-\(attempt).txt")
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/python3")
            process.arguments = [fixture.path, file.path, portFile.path] + (slow ? ["slow"] : [])
            try process.run()
            let deadline = Date().addingTimeInterval(10)
            while !FileManager.default.fileExists(atPath: portFile.path), Date() < deadline, process.isRunning {
                Thread.sleep(forTimeInterval: 0.03)
            }
            if let text = try? String(contentsOf: portFile, encoding: .utf8),
               let port = Int(text.trimmingCharacters(in: .whitespacesAndNewlines)) {
                return Server(process: process, baseURL: URL(string: "http://127.0.0.1:\(port)")!)
            }
            process.terminate(); process.waitUntilExit()
            Thread.sleep(forTimeInterval: 0.2)
        }
        throw NSError(domain: "DownloadEngineIsolationTests", code: 1)
    }

    private func root(_ name: String) -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("valora-download-\(name)-\(UUID().uuidString)", isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeSource(_ root: URL, size: Int = 20 * 1024 * 1024) throws -> URL {
        let url = root.appendingPathComponent("source.bin")
        let data = Data(repeating: 0xA7, count: size)
        try data.write(to: url)
        return url
    }

    private func waitForItem(_ service: DownloadEngineService, id: UUID,
                             timeout: TimeInterval = 15) async -> DownloadItemSnapshot? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let item = service.items.first(where: { $0.id == id }) { return item }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return nil
    }

    private func waitForState(_ service: DownloadEngineService, id: UUID,
                              states: Set<DownloadItemState>, timeout: TimeInterval = 15) async -> DownloadItemSnapshot? {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if let item = service.items.first(where: { $0.id == id }), states.contains(item.state) { return item }
            try? await Task.sleep(for: .milliseconds(25))
        }
        return nil
    }

    func testRealRangeDownloadSegmentsPauseResumeAndFileHash() async throws {
        let root = root("real")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceFile = try makeSource(root)
        let sourceData = try Data(contentsOf: sourceFile)
        let server = try startServer(file: sourceFile, root: root)
        defer { server.stop() }
        let env = ValoraDownloadEnvironment.qa(root: root, suite: "valora.download.test.\(UUID().uuidString)")
        env.settings.autoStartDownloads = false
        let service = DownloadEngineService(environment: env)
        let destination = root.appendingPathComponent("downloads/result.bin")
        try await service.enqueue(source: server.baseURL.appendingPathComponent("source.bin"), destination: destination)
        let id = try XCTUnwrap(service.items.first?.id)
        try await service.resume(id: id)
        var sawActiveSegments = false
        let activeDeadline = Date().addingTimeInterval(8)
        while Date() < activeDeadline {
            if let item = service.items.first(where: { $0.id == id }), item.activeSegments > 0 {
                sawActiveSegments = true
                await service.pause(id: id)
                break
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertTrue(sawActiveSegments, "real engine must expose active segment spans before pause")
        let paused = await waitForState(service, id: id, states: [.paused], timeout: 5)
        XCTAssertNotNil(paused)
        try await service.resume(id: id)
        let complete = await waitForState(service, id: id, states: [.completed, .failed], timeout: 40)
        XCTAssertEqual(complete?.state, .completed)
        XCTAssertGreaterThan(complete?.segments.count ?? 0, 1, "completed task must retain its multi-segment map")
        XCTAssertEqual(try Data(contentsOf: destination), sourceData)
        XCTAssertGreaterThanOrEqual(complete?.downloadedBytes ?? 0, 20 * 1024 * 1024)
        let completedData = try Data(contentsOf: destination)
        try? await service.enqueue(source: server.baseURL.appendingPathComponent("source.bin"),
                                   destination: destination)
        XCTAssertTrue(service.hasPendingConflict, "same source/destination must use the native duplicate flow")
        XCTAssertEqual(try Data(contentsOf: destination), completedData)
        _ = await service.delete(id: id, moveFilesToTrash: false)
        XCTAssertTrue(FileManager.default.fileExists(atPath: destination.path), "record deletion without trash keeps the finished file")
    }

    func testPartialPauseSaveRestartRestoresSameTaskAndProgress() async throws {
        let root = root("partial-restart")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceFile = try makeSource(root, size: 2 * 1024 * 1024)
        let sourceData = try Data(contentsOf: sourceFile)
        let server = try startServer(file: sourceFile, root: root, slow: true)
        defer { server.stop() }
        let env = ValoraDownloadEnvironment.qa(root: root, suite: "valora.download.partial.\(UUID().uuidString)")
        env.settings.autoStartDownloads = false
        env.settings.defaultSegmentCount = 4
        var manager: DownloadManager? = DownloadManager(environment: env)
        let destination = root.appendingPathComponent("downloads/partial.bin")
        let task = try await manager!.addDownload(
            url: URL(string: "\(server.baseURL.absoluteString)/source.bin?slow=1")!,
            destination: destination)
        let id = task.id
        // Resume from a task we own so pause can be awaited deterministically.
        let running = Task { try? await manager!.resumeDownload(task) }
        func bytesInScratch() -> Int64 {
            let files = (try? FileManager.default.contentsOfDirectory(
                at: env.scratchContainer, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            return files.reduce(Int64(0)) { total, url in
                guard url.lastPathComponent.contains(id.uuidString),
                      let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize else { return total }
                return total + Int64(size)
            }
        }
        var partial: Int64 = 0
        let deadline = Date().addingTimeInterval(15)
        while Date() < deadline {
            let onDisk = bytesInScratch()
            if task.status == .downloading, onDisk > 0 {
                partial = onDisk
                break
            }
            try? await Task.sleep(for: .milliseconds(20))
        }
        XCTAssertGreaterThan(partial, 0, "must observe real partial bytes on disk before pause")
        await manager!.pauseDownload(task)
        await running.value
        XCTAssertEqual(task.status, .paused)
        manager!.saveBeforeTermination()
        let partialBytes = max(task.downloadedBytes, bytesInScratch())
        XCTAssertGreaterThan(partialBytes, 0)
        let scratchNamesBefore = (try? FileManager.default.contentsOfDirectory(atPath: env.scratchContainer.path)) ?? []
        XCTAssertTrue(scratchNamesBefore.contains { $0.contains(id.uuidString) },
                      "the real segment scratch must survive pause and save")
        manager = nil
        try? await Task.sleep(for: .milliseconds(500))

        // Recreate the manager in the same explicit root. The old lock must be
        // released and the new owner must restore the same task and partial bytes.
        var restarted: DownloadManager? = DownloadManager(environment: env)
        XCTAssertTrue(restarted!.ownsDownloadList)
        let restored = restarted!.tasks.first(where: { $0.id == id })
        XCTAssertNotNil(restored)
        XCTAssertEqual(restored?.id, id)
        XCTAssertEqual(restored?.status, .paused)
        XCTAssertGreaterThanOrEqual(restored?.downloadedBytes ?? 0, partialBytes)
        let scratchNamesAfter = (try? FileManager.default.contentsOfDirectory(atPath: env.scratchContainer.path)) ?? []
        XCTAssertTrue(scratchNamesAfter.contains { $0.contains(id.uuidString) },
                      "restored task must still own its partial segment files")

        try await restarted!.resumeDownload(try XCTUnwrap(restored))
        XCTAssertEqual(restored?.status, .completed)
        XCTAssertEqual(try Data(contentsOf: destination), sourceData)
        XCTAssertEqual(restored?.downloadedBytes, Int64(sourceData.count))
        restarted = nil
    }

    func testDownloadMenuModelUsesRealLocalRangeEngine() async throws {
        let root = root("menu-real")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceFile = try makeSource(root, size: 2 * 1024 * 1024)
        let server = try startServer(file: sourceFile, root: root)
        defer { server.stop() }
        let env = ValoraDownloadEnvironment.qa(root: root, suite: "valora.download.menu.\(UUID().uuidString)")
        env.settings.autoStartDownloads = false
        let service = DownloadEngineService(environment: env)
        let model = DownloadMenuModel(service: service)
        let destination = root.appendingPathComponent("downloads/menu-real.bin")
        try await model.enqueue(source: server.baseURL.appendingPathComponent("source.bin"),
                                destination: destination)
        let id = try XCTUnwrap(model.items.first?.id)
        XCTAssertEqual(model.items.first?.state, .paused)
        try await model.resume(id)
        let deadline = Date().addingTimeInterval(30)
        while Date() < deadline {
            if model.items.first(where: { $0.id == id })?.state == .completed { break }
            try? await Task.sleep(for: .milliseconds(40))
            model.refresh()
        }
        let completed = try XCTUnwrap(model.items.first(where: { $0.id == id }))
        XCTAssertEqual(completed.state, .completed)
        XCTAssertGreaterThan(completed.downloadedBytes, 0)
        XCTAssertEqual(try Data(contentsOf: destination).count, 2 * 1024 * 1024)
        model.stopTimer()
    }

    func testDownloadFeatureOffPausesSavesAndDoesNotDeletePartial() async throws {
        let root = root("feature-off")
        defer { try? FileManager.default.removeItem(at: root) }
        let sourceFile = try makeSource(root, size: 4 * 1024 * 1024)
        let server = try startServer(file: sourceFile, root: root, slow: true)
        defer { server.stop() }
        let env = ValoraDownloadEnvironment.qa(root: root, suite: "valora.download.off.\(UUID().uuidString)")
        env.settings.autoStartDownloads = false
        let service = DownloadEngineService(environment: env)
        let controller = DownloadMenuBarController(service: service, onSettings: {}, onQuit: {},
                                                   animates: false)
        controller.start()
        defer { service.manager.saveBeforeTermination(); controller.model.stopTimer() }
        let destination = root.appendingPathComponent("downloads/off.bin")
        try await controller.model.enqueue(source: server.baseURL.appendingPathComponent("source.bin"),
                                           destination: destination)
        let id = try XCTUnwrap(controller.model.items.first?.id)
        try await controller.model.resume(id)
        let deadline = Date().addingTimeInterval(10)
        while Date() < deadline {
            if let task = service.manager.tasks.first(where: { $0.id == id }),
               task.downloadedBytes > 0, task.status == .downloading { break }
            try? await Task.sleep(for: .milliseconds(25))
        }
        let task = try XCTUnwrap(service.manager.tasks.first(where: { $0.id == id }))
        XCTAssertGreaterThan(task.downloadedBytes, 0)
        let beforeBytes = task.downloadedBytes
        await controller.suspendAndStop()
        XCTAssertEqual(task.status, .paused)
        XCTAssertEqual(service.manager.activeCount, 0)
        XCTAssertEqual(task.downloadedBytes, beforeBytes)
        XCTAssertTrue((try? FileManager.default.contentsOfDirectory(atPath: env.scratchContainer.path))?.contains { $0.contains(id.uuidString) } ?? false)

        try? await Task.sleep(for: .milliseconds(900))
        XCTAssertEqual(task.downloadedBytes, beforeBytes, "paused feature-off task must not advance")
        let scratchAfter = (try? FileManager.default.contentsOfDirectory(atPath: env.scratchContainer.path)) ?? []
        XCTAssertTrue(scratchAfter.contains { $0.contains(id.uuidString) }, "feature off must not delete partial scratch")

        controller.start()
        XCTAssertTrue(controller.isPopoverShown == false)
        XCTAssertEqual(controller.model.items.first(where: { $0.id == id })?.state, .paused)
        XCTAssertEqual(service.manager.activeCount, 0)
        controller.stop()
    }

    func testUnavailableStorageRejectsAddBeforeScratchOrNetwork() async throws {
        let root = root("unavailable")
        defer { try? FileManager.default.removeItem(at: root) }
        let support = root.appendingPathComponent("support", isDirectory: false)
        try Data("not-a-directory".utf8).write(to: support)
        let suite = "valora.download.unavailable.\(UUID().uuidString)"
        let env = ValoraDownloadEnvironment.qa(root: root, suite: suite)
        // Replace only the persistence location with a path whose parent is a
        // regular file, so both directory creation and lock acquisition fail.
        let broken = DownloadEnvironment(
            persistenceURL: support.appendingPathComponent("downloads.json"),
            scratchContainer: root.appendingPathComponent("scratch"),
            defaults: env.defaults,
            defaultDownloadDirectory: root.appendingPathComponent("downloads"),
            allowExternalHelpers: false,
            measureTemporaryStorageAtLaunch: true)
        let blocked = DownloadEngineService(environment: broken)
        XCTAssertFalse(blocked.manager.ownsDownloadList)
        XCTAssertNotNil(blocked.manager.downloadListUnavailableReason)
        XCTAssertFalse(FileManager.default.fileExists(atPath: broken.scratchContainer.path))
        do {
            try await blocked.enqueue(source: URL(string: "http://127.0.0.1:1/fixture.bin")!,
                                      destination: root.appendingPathComponent("downloads/fixture.bin"))
            XCTFail("an unavailable manager must reject new downloads")
        } catch DownloadError.storageUnavailable {
            // expected
        } catch {
            XCTFail("unexpected error: \(error)")
        }
        XCTAssertTrue(blocked.items.isEmpty)
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("downloads/fixture.bin").path))
    }

    func testCancellationAndABIsolation() async throws {
        let rootA = root("a"), rootB = root("b")
        defer { try? FileManager.default.removeItem(at: rootA); try? FileManager.default.removeItem(at: rootB) }
        let sourceFile = try makeSource(rootA, size: 4 * 1024 * 1024)
        let sourceData = try Data(contentsOf: sourceFile)
        let server = try startServer(file: sourceFile, root: rootA)
        defer { server.stop() }
        let sentinel = rootB.appendingPathComponent("sentinel.txt")
        try Data("b-only".utf8).write(to: sentinel)
        let envA = ValoraDownloadEnvironment.qa(root: rootA, suite: "valora.download.a.\(UUID().uuidString)")
        let envB = ValoraDownloadEnvironment.qa(root: rootB, suite: "valora.download.b.\(UUID().uuidString)")
        envA.settings.autoStartDownloads = false
        let serviceA = DownloadEngineService(environment: envA)
        let serviceB = DownloadEngineService(environment: envB)
        try await serviceA.enqueue(source: server.baseURL.appendingPathComponent("source.bin"),
                                   destination: rootA.appendingPathComponent("downloads/cancel.bin"))
        let id = try XCTUnwrap(serviceA.items.first?.id)
        try await serviceA.resume(id: id)
        try? await Task.sleep(for: .milliseconds(300))
        await serviceA.cancel(id: id)
        XCTAssertTrue(serviceA.items.isEmpty)
        let leftovers = (try? FileManager.default.contentsOfDirectory(atPath: envA.scratchContainer.path)) ?? []
        XCTAssertTrue(leftovers.allSatisfy { !$0.contains(id.uuidString) })
        XCTAssertEqual(try Data(contentsOf: sentinel), Data("b-only".utf8))
        XCTAssertTrue(serviceB.items.isEmpty)
        XCTAssertTrue(try Data(contentsOf: sourceFile) == sourceData)

        // Explicit trash moves the completed file only inside the injected root.
        let trashDestination = rootA.appendingPathComponent("downloads/trash.bin")
        try await serviceA.enqueue(source: server.baseURL.appendingPathComponent("source.bin"),
                                   destination: trashDestination)
        let trashID = try XCTUnwrap(serviceA.items.first?.id)
        try await serviceA.resume(id: trashID)
        let trashComplete = await waitForState(serviceA, id: trashID, states: [.completed, .failed], timeout: 25)
        XCTAssertEqual(trashComplete?.state, .completed)
        await serviceA.delete(id: trashID, moveFilesToTrash: true)
        XCTAssertFalse(FileManager.default.fileExists(atPath: trashDestination.path))
        XCTAssertTrue(FileManager.default.fileExists(atPath: rootA.appendingPathComponent("trash/trash.bin").path))

        try await serviceA.enqueue(source: URL(string: "file:///valora-not-a-download")!,
                                   destination: rootA.appendingPathComponent("downloads/invalid.bin"))
        let failedID = try XCTUnwrap(serviceA.items.first?.id)
        try await serviceA.resume(id: failedID)
        let failed = await waitForState(serviceA, id: failedID, states: [.failed], timeout: 5)
        XCTAssertNotNil(failed)
        XCTAssertEqual(serviceA.manager.activeCount, 0)
    }

    func testRestartLockAndUnreadableStateStayInsideRoot() async throws {
        let root = root("restart")
        defer { try? FileManager.default.removeItem(at: root) }
        let suite = "valora.download.restart.\(UUID().uuidString)"
        let env = ValoraDownloadEnvironment.qa(root: root, suite: suite)
        env.settings.autoStartDownloads = false
        let sourceFile = try makeSource(root, size: 2 * 1024 * 1024)
        let server = try startServer(file: sourceFile, root: root)
        defer { server.stop() }
        var service: DownloadEngineService? = DownloadEngineService(environment: env)
        try await service!.enqueue(source: server.baseURL.appendingPathComponent("source.bin"),
                                   destination: root.appendingPathComponent("downloads/persist.bin"))
        let id = try XCTUnwrap(service!.items.first?.id)
        try await service!.resume(id: id)
        let complete = await waitForState(service!, id: id, states: [.completed, .failed], timeout: 25)
        XCTAssertEqual(complete?.state, .completed)
        service?.manager.saveBeforeTermination()
        service = nil
        try? await Task.sleep(for: .milliseconds(150))

        // A second manager at the same explicit root loads only its own record.
        let envB = DownloadEnvironment(
            persistenceURL: env.persistenceURL,
            scratchContainer: env.scratchContainer,
            defaults: env.defaults,
            defaultDownloadDirectory: root.appendingPathComponent("downloads"),
            allowExternalHelpers: false,
            measureTemporaryStorageAtLaunch: false)
        let restarted = DownloadEngineService(environment: envB)
        XCTAssertEqual(restarted.items.count, 1)
        XCTAssertEqual(restarted.items.first?.id, id)
        XCTAssertEqual(restarted.items.first?.state, .completed)

        // A concurrent manager cannot own the same list; its own root remains separate.
        let envC = DownloadEnvironment(
            persistenceURL: env.persistenceURL,
            scratchContainer: env.scratchContainer,
            defaults: env.defaults,
            defaultDownloadDirectory: root.appendingPathComponent("downloads"),
            allowExternalHelpers: false,
            measureTemporaryStorageAtLaunch: false)
        let blocked = DownloadEngineService(environment: envC)
        XCTAssertFalse(blocked.manager.ownsDownloadList)

        // An unreadable list is moved aside in its own persistence directory.
        let rootD = self.root("unreadable")
        defer { try? FileManager.default.removeItem(at: rootD) }
        let envD = ValoraDownloadEnvironment.qa(root: rootD, suite: "valora.download.unreadable.\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: envD.persistenceURL.deletingLastPathComponent(),
                                                withIntermediateDirectories: true)
        try Data("not-json".utf8).write(to: envD.persistenceURL)
        _ = DownloadEngineService(environment: envD)
        let names = (try? FileManager.default.contentsOfDirectory(atPath: envD.persistenceURL.deletingLastPathComponent().path)) ?? []
        XCTAssertTrue(names.contains { $0.contains("downloads-unreadable-") })
    }
}
