import Foundation
import XCTest
import DownloadEngine

@MainActor
final class IndependentDownloadStorageTests: XCTestCase {
    func testManagerWithoutLockCannotClearOwnersPartialFiles() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("valora-independent-cleanup-\(UUID().uuidString)")
        let suite = "valora.independent.cleanup.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let environment = DownloadEnvironment(
            persistenceURL: root.appendingPathComponent("downloads.json"),
            scratchContainer: root.appendingPathComponent("scratch"),
            defaults: defaults)
        environment.settings.autoStartDownloads = false
        let owner = DownloadManager(environment: environment)
        let task = try await owner.addDownload(
            url: URL(string: "http://127.0.0.1:1/fixture.bin")!,
            destination: root.appendingPathComponent("fixture.bin"))
        let partial = environment.scratchContainer.appendingPathComponent("\(task.id.uuidString)-segment-0.tmp")
        let bytes = Data("owner-partial-data".utf8)
        try bytes.write(to: partial)
        let blocked = DownloadManager(environment: environment)
        XCTAssertFalse(blocked.ownsDownloadList)
        _ = await blocked.clearOrphanedTemporaryFiles()
        XCTAssertEqual(try? Data(contentsOf: partial), bytes,
                       "a lock-denied manager has an empty task list and must not classify the owner's partial bytes as orphaned")
        withExtendedLifetime((owner, blocked)) {}
    }

    func testFreshNestedStorageAcquiresLockBeforeAnotherManagerCanOwnIt() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("valora-independent-lock-\(UUID().uuidString)")
        let suite = "valora.independent.lock.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer {
            defaults.removePersistentDomain(forName: suite)
            try? FileManager.default.removeItem(at: root)
        }
        let environment = DownloadEnvironment(
            persistenceURL: root.appendingPathComponent("support/downloads.json"),
            scratchContainer: root.appendingPathComponent("scratch"),
            defaults: defaults)
        let first = DownloadManager(environment: environment)
        let second = DownloadManager(environment: environment)
        XCTAssertTrue(first.ownsDownloadList)
        XCTAssertFalse(second.ownsDownloadList, "fresh parent directory must exist before acquiring the first lock")
        withExtendedLifetime((first, second)) {}
    }
}
