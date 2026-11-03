import AppKit
import ChromeBridgeKit
import Darwin
import Foundation

/// Owns the Valora side of the Chrome-only native messaging bridge. It is
/// created only when the accepted Downloads feature starts; when Downloads is
/// switched off the listener is closed and removed before the engine pauses.
@MainActor
final class ChromeBridgeController {
    typealias PeerVerifier = @Sendable (Int32) -> ChromePeerVerification.Outcome

    let service: DownloadServicing
    let socketPath: String
    var onStateChange: (() -> Void)?
    private(set) var lastHandshakeAt: Date?
    private(set) var lastFailure: String?
    private(set) var acceptedRequestCount = 0
    private(set) var requestGeneration: UInt64 = 0
    private var serverFD: Int32?
    private var clientTasks: [Task<Void, Never>] = []
    private let peerVerifier: PeerVerifier
    private nonisolated(unsafe) var accepting = false

    init(service: DownloadServicing,
         socketPath: String = ChromeBridgeSocket.currentPath,
         peerVerifier: @escaping PeerVerifier = { fd in
             ChromePeerVerification.verifyPeer(onSocket: fd, expecting: .nativeMessagingHost)
         }) {
        self.service = service
        self.socketPath = socketPath
        self.peerVerifier = peerVerifier
    }

    var isRunning: Bool { serverFD != nil && accepting }

    @discardableResult
    func start() -> Bool {
        guard serverFD == nil else { return true }
        guard !anotherInstanceIsListening() else {
            lastFailure = "另一个 Valora 进程已占用 Chrome 桥接 socket"
            onStateChange?()
            return false
        }
        unlink(socketPath)
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else {
            lastFailure = "无法创建 Chrome 桥接 socket"
            onStateChange?()
            return false
        }
        let (address, length) = ChromeBridgeSocket.makeAddress(path: socketPath)
        var mutable = address
        let previousUmask = umask(0o077)
        let bound = withUnsafePointer(to: &mutable) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { bind(fd, $0, length) }
        }
        umask(previousUmask)
        guard bound == 0, listen(fd, 5) == 0 else {
            close(fd)
            lastFailure = "无法监听 Chrome 桥接 socket"
            onStateChange?()
            return false
        }
        _ = chmod(socketPath, 0o600)
        serverFD = fd
        accepting = true
        requestGeneration &+= 1
        lastFailure = nil
        onStateChange?()
        DispatchQueue.global().async { [weak self] in
            self?.acceptLoop(fd)
        }
        return true
    }

    func stop() {
        guard serverFD != nil || accepting else { return }
        accepting = false
        requestGeneration &+= 1
        if let fd = serverFD {
            close(fd)
            serverFD = nil
        }
        for task in clientTasks { task.cancel() }
        clientTasks.removeAll()
        unlink(socketPath)
        onStateChange?()
    }

    private func anotherInstanceIsListening() -> Bool {
        let probe = socket(AF_UNIX, SOCK_STREAM, 0)
        guard probe >= 0 else { return false }
        defer { close(probe) }
        let (address, length) = ChromeBridgeSocket.makeAddress(path: socketPath)
        var mutable = address
        return withUnsafePointer(to: &mutable) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { connect(probe, $0, length) }
        } == 0
    }

    private nonisolated func acceptLoop(_ fd: Int32) {
        while accepting {
            let client = accept(fd, nil, nil)
            guard client >= 0 else {
                if !accepting { break }
                usleep(20_000)
                continue
            }
            var noSigPipe: Int32 = 1
            setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
            Task.detached { [weak self] in
                await self?.handleClient(client)
            }
        }
    }

    private nonisolated func handleClient(_ fd: Int32) async {
        defer { close(fd) }
        guard peerVerifier(fd).isTrusted else {
            await MainActor.run { [weak self] in
                self?.lastFailure = "Chrome 桥接对端签名校验失败"
                self?.onStateChange?()
            }
            return
        }
        var timeout = timeval(tv_sec: 3, tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &timeout, socklen_t(MemoryLayout<timeval>.size))
        let handle = FileHandle(fileDescriptor: fd, closeOnDealloc: false)
        guard let object = try? ChromeNativeFraming.readJSON(from: handle) else { return }
        let data = await process(object)
        guard let framed = try? ChromeNativeFraming.encode(data) else { return }
        _ = framed.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
    }

    private func process(_ object: [String: Any]) async -> Data {
        guard isRunning else { return json(["ok": false, "error": "Chrome 桥接已关闭"]) }
        do {
            try ChromeBridgeProtocol.validateEnvelope(object)
        } catch {
            lastFailure = error.localizedDescription
            onStateChange?()
            return json(["ok": false, "error": error.localizedDescription])
        }
        guard let type = object["type"] as? String else {
            return json(["ok": false, "error": "无效请求"])
        }
        switch type {
        case "hello":
            lastHandshakeAt = Date()
            lastFailure = nil
            acceptedRequestCount += 1
            onStateChange?()
            return json(ChromeBridgeProtocol.helloResponse(appVersion: Self.appVersion))
        case "download":
            acceptedRequestCount += 1
            let generation = requestGeneration
            guard let raw = object["url"] as? String,
                  let url = try? ChromeBridgeProtocol.validateDownloadURL(raw) else {
                return json(["ok": false, "error": ChromeBridgeProtocolError.invalidURL.localizedDescription])
            }
            let name: String
            do {
                name = try ChromeBridgeProtocol.validateFilename(object["filename"] as? String)
                    ?? (url.lastPathComponent.isEmpty ? "download" : url.lastPathComponent)
            } catch {
                return json(["ok": false, "error": error.localizedDescription])
            }
            let destination = service.defaultDownloadDirectory.appendingPathComponent(name)
            guard isRunning, requestGeneration == generation else {
                return json(["ok": false, "error": "Chrome 桥接已关闭"])
            }
            do {
                try await service.enqueue(source: url, destination: destination)
                onStateChange?()
                return json(["ok": true, "accepted": true,
                             "protocolVersion": ValoraChromeBridge.protocolVersion,
                             "app": ValoraChromeBridge.appName,
                             "appBundleIdentifier": ValoraChromeBridge.appBundleIdentifier,
                             "filename": name])
            } catch {
                lastFailure = error.localizedDescription
                onStateChange?()
                return json(["ok": false, "error": error.localizedDescription])
            }
        case "getDownloads":
            acceptedRequestCount += 1
            let downloads = service.items.map { item in
                [
                    "id": item.id.uuidString,
                    "filename": item.filename,
                    "url": item.sourceURL,
                    "progress": item.progress,
                    "status": item.state.rawValue,
                    "speed": item.speed,
                    "totalBytes": item.totalBytes,
                    "downloadedBytes": item.downloadedBytes
                ] as [String: Any]
            }
            return json(["ok": true, "downloads": downloads])
        case "pause", "resume", "cancel":
            acceptedRequestCount += 1
            guard let raw = object["id"] as? String, let id = UUID(uuidString: raw) else {
                return json(["ok": false, "error": "无效下载 ID"])
            }
            switch type {
            case "pause": await service.pause(id: id)
            case "resume":
                do { try await service.resume(id: id) }
                catch { return json(["ok": false, "error": error.localizedDescription]) }
            case "cancel": await service.cancel(id: id)
            default: break
            }
            return json(["ok": true])
        default:
            return json(["ok": false, "error": "未知的 Valora 请求"])
        }
    }

    private func json(_ object: [String: Any]) -> Data {
        (try? JSONSerialization.data(withJSONObject: object)) ?? Data()
    }

    private static var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "unknown"
    }
}
