import CryptoKit
import Foundation
import ReferenceCore

/// Bounded memory + disk cache for validated successful lyrics only.
/// File names are hashes; no song text appears in the directory or filename.
actor LyricsCache {
    private struct Entry {
        let result: LyricsFetchResult
        let bytes: Int
    }

    let directory: URL
    let memoryEntryLimit: Int
    let memoryPayloadLimit: Int
    let diskByteLimit: Int
    private var memory: [String: Entry] = [:]
    private var order: [String] = []
    private var memoryBytes = 0

    init(directory: URL? = nil,
         memoryEntryLimit: Int = 50,
         memoryPayloadLimit: Int = 5 * 1024 * 1024,
         diskByteLimit: Int = 50 * 1024 * 1024) {
        self.directory = directory ?? Self.defaultDirectory
        self.memoryEntryLimit = max(1, memoryEntryLimit)
        self.memoryPayloadLimit = max(1, memoryPayloadLimit)
        self.diskByteLimit = max(1, diskByteLimit)
    }

    static var defaultDirectory: URL {
        let base = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("com.wangqing.valora/Lyrics", isDirectory: true)
    }

    func get(_ key: String) -> LyricsFetchResult? {
        if let entry = memory[key] {
            touch(key)
            return entry.result
        }
        let url = fileURL(key)
        guard let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize,
              size <= memoryPayloadLimit,
              let data = try? Data(contentsOf: url),
              let result = try? JSONDecoder().decode(LyricsFetchResult.self, from: data),
              Self.isCacheable(result) else {
            try? FileManager.default.removeItem(at: url)
            return nil
        }
        addMemory(key, result: result, bytes: data.count)
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        return result
    }

    func put(_ key: String, result: LyricsFetchResult) {
        guard Self.isCacheable(result),
              let data = try? JSONEncoder().encode(result),
              data.count <= memoryPayloadLimit else { return }
        addMemory(key, result: result, bytes: data.count)
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = fileURL(key)
        // Data's atomic write creates a sibling temporary file and renames it.
        try? data.write(to: url, options: [.atomic])
        try? FileManager.default.setAttributes([.modificationDate: Date()], ofItemAtPath: url.path)
        evictDiskIfNeeded()
    }

    func memoryStats() -> (count: Int, bytes: Int) { (memory.count, memoryBytes) }

    func diskStats() -> (count: Int, bytes: Int) {
        let files = diskFiles()
        return (files.count, files.reduce(0) { $0 + $1.bytes })
    }

    private func fileURL(_ key: String) -> URL {
        let digest = SHA256.hash(data: Data(key.utf8)).map { String(format: "%02x", $0) }.joined()
        return directory.appendingPathComponent(digest + ".json")
    }

    private func touch(_ key: String) {
        order.removeAll { $0 == key }
        order.append(key)
    }

    private func addMemory(_ key: String, result: LyricsFetchResult, bytes: Int) {
        if let old = memory[key] { memoryBytes -= old.bytes }
        memory[key] = Entry(result: result, bytes: bytes)
        memoryBytes += bytes
        touch(key)
        while memory.count > memoryEntryLimit || memoryBytes > memoryPayloadLimit {
            guard let oldest = order.first else { break }
            order.removeFirst()
            if let entry = memory.removeValue(forKey: oldest) { memoryBytes -= entry.bytes }
        }
    }

    private struct DiskFile { let url: URL; let bytes: Int; let modified: Date }

    private func diskFiles() -> [DiskFile] {
        guard let urls = try? FileManager.default.contentsOfDirectory(at: directory,
            includingPropertiesForKeys: [.fileSizeKey, .contentModificationDateKey],
            options: [.skipsHiddenFiles]) else { return [] }
        return urls.compactMap { url in
            guard let values = try? url.resourceValues(forKeys: [.isRegularFileKey, .fileSizeKey, .contentModificationDateKey]),
                  values.isRegularFile == true else { return nil }
            return DiskFile(url: url, bytes: values.fileSize ?? 0,
                            modified: values.contentModificationDate ?? .distantPast)
        }
    }

    private func evictDiskIfNeeded() {
        var files = diskFiles().sorted { $0.modified < $1.modified }
        var total = files.reduce(0) { $0 + $1.bytes }
        while total > diskByteLimit, !files.isEmpty {
            let oldest = files.removeFirst()
            total -= oldest.bytes
            try? FileManager.default.removeItem(at: oldest.url)
        }
    }

    private static func isCacheable(_ result: LyricsFetchResult) -> Bool {
        switch result {
        case .timed, .wordTimed: return true
        case .noLyrics, .instrumental, .unsynchronized: return false
        }
    }
}
