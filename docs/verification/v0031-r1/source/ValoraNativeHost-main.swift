import AppKit
import ChromeBridgeKit
import Foundation

/// One-shot Chrome native-messaging host. Chrome starts this signed sibling of
/// Valora.app for each sendNativeMessage call, supplies one framed JSON
/// message on stdin, and expects exactly one framed JSON reply on stdout.
/// The host only speaks to the code-signature-verified Valora app over a
/// local Unix socket. It does not read Chrome cookies, history or web pages.
final class ValoraNativeHostRunner {
    private let appBundleIdentifier = ValoraChromeBridge.appBundleIdentifier

    func run() -> Int32 {
        do {
            guard let message = try ChromeNativeFraming.readJSON(from: .standardInput) else {
                return 0
            }
            let response = try handle(message)
            try ChromeNativeFraming.writeJSON(response, to: .standardOutput)
            return 0
        } catch let error as ChromeBridgeProtocolError {
            try? writeError(error.errorDescription ?? "请求无效")
            return 1
        } catch {
            try? writeError("Valora Chrome 桥接请求失败")
            return 1
        }
    }

    private func handle(_ message: [String: Any]) throws -> [String: Any] {
        // Chrome passes the calling extension origin as the first process
        // argument. Reject a direct/old host invocation before doing anything.
        let origin = CommandLine.arguments.dropFirst().first
        guard origin == "chrome-extension://\(ValoraChromeBridge.extensionID)/" else {
            throw ChromeBridgeProtocolError.wrongOrigin(origin)
        }
        // Validate the caller's version before rewriting any request into
        // Valora's current envelope. Missing, non-integer and old versions
        // must fail here, not be relabeled as version 1.
        guard let version = message["protocolVersion"] as? Int,
              version == ValoraChromeBridge.protocolVersion else {
            throw ChromeBridgeProtocolError.unsupportedVersion(message["protocolVersion"] as? Int)
        }
        guard let type = message["type"] as? String else {
            throw ChromeBridgeProtocolError.invalidMessage
        }
        switch type {
        case "ping", "status":
            let result = sendToApp(ChromeBridgeProtocol.hello())
            if let result {
                try ChromeBridgeProtocol.validateAppResponse(result)
                return [
                    "ok": true,
                    "appRunning": true,
                    "bridgeEnabled": true,
                    "protocolVersion": ValoraChromeBridge.protocolVersion,
                    "app": ValoraChromeBridge.appName,
                    "appVersion": result["appVersion"] as? String ?? "unknown",
                    "bridge": ValoraChromeBridge.hostName
                ]
            }
            let appRunning = NSRunningApplication.runningApplications(
                withBundleIdentifier: appBundleIdentifier).contains { !$0.isTerminated }
            return ["ok": true, "appRunning": appRunning, "bridgeEnabled": false,
                    "protocolVersion": ValoraChromeBridge.protocolVersion,
                    "app": ValoraChromeBridge.appName,
                    "error": appRunning ? "Valora download feature or bridge is disabled" : "Valora app not running"]
        case "download":
            guard let raw = message["url"] as? String else {
                throw ChromeBridgeProtocolError.invalidURL
            }
            _ = try ChromeBridgeProtocol.validateDownloadURL(raw)
            let request = try downloadRequest(from: message)
            guard let result = sendToApp(request) else {
                return ["ok": false, "appRunning": false,
                        "error": "Valora app not running"]
            }
            return result
        case "launchApp":
            return try launchApp()
        case "getDownloads", "pause", "resume", "cancel":
            guard let result = sendToApp(try operationRequest(from: message)) else {
                return ["ok": false, "appRunning": false, "error": "Valora app not running"]
            }
            return result
        default:
            throw ChromeBridgeProtocolError.invalidMessage
        }
    }

    private func downloadRequest(from message: [String: Any]) throws -> [String: Any] {
        var request: [String: Any] = [
            "type": "download",
            "protocolVersion": ValoraChromeBridge.protocolVersion,
            "app": ValoraChromeBridge.appName,
            "hostName": ValoraChromeBridge.hostName,
            "appBundleIdentifier": ValoraChromeBridge.appBundleIdentifier
        ]
        for key in ["url", "referrer", "filename", "requestID"] {
            if let value = message[key] as? String { request[key] = value }
        }
        return request
    }

    private func operationRequest(from message: [String: Any]) throws -> [String: Any] {
        var request: [String: Any] = [
            "protocolVersion": ValoraChromeBridge.protocolVersion,
            "app": ValoraChromeBridge.appName,
            "hostName": ValoraChromeBridge.hostName,
            "appBundleIdentifier": ValoraChromeBridge.appBundleIdentifier
        ]
        request["type"] = message["type"]
        for key in ["id", "requestID"] {
            if let value = message[key] as? String { request[key] = value }
        }
        return request
    }

    private func sendToApp(_ object: [String: Any]) -> [String: Any]? {
        guard let fd = ChromeBridgeSocket.connect(path: ChromeBridgeSocket.currentPath) else {
            return nil
        }
        defer { close(fd) }
        guard ChromePeerVerification.verifyPeer(onSocket: fd, expecting: .app).isTrusted else {
            return nil
        }
        guard let body = try? JSONSerialization.data(withJSONObject: object),
              let framed = try? ChromeNativeFraming.encode(body) else { return nil }
        let wrote = framed.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
        guard wrote == framed.count else { return nil }
        shutdown(fd, SHUT_WR)
        let response = ChromeBridgeSocket.readToEnd(fd: fd)
        return try? ChromeNativeFraming.decodeSingleJSON(response)
    }

    private func launchApp() throws -> [String: Any] {
        guard let own = ChromePeerVerification.ownExecutableURL() else {
            return ["ok": false, "error": "无法定位 Valora.app"]
        }
        let app = own.deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        guard app.pathExtension == "app",
              FileManager.default.fileExists(atPath: app.path) else {
            return ["ok": false, "error": "本地桥接不在 Valora.app 内"]
        }
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = [app.path]
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return ["ok": false, "error": "无法打开 Valora：\(error.localizedDescription)"]
        }
        guard process.terminationStatus == 0 else {
            return ["ok": false, "error": "无法打开 Valora（open 退出码 \(process.terminationStatus)）"]
        }
        return ["ok": true, "appRunning": true]
    }

    private func writeError(_ message: String) throws {
        try ChromeNativeFraming.writeJSON(["ok": false, "error": message], to: .standardOutput)
    }
}

exit(ValoraNativeHostRunner().run())
