import CryptoKit
import Darwin
import Foundation
import XCTest
@testable import Valora
import ChromeBridgeKit

final class ChromeBridgeProtocolTests: XCTestCase {
    func testExtensionManifestIdentityAndLimitedPermissions() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let directory = root.appendingPathComponent("Resources/ChromeExtension")
        let manifest = try ChromeBridgeExtensionManifest.load(from: directory)
        try ChromeBridgeExtensionManifest.validate(manifest)
        XCTAssertEqual(manifest["name"] as? String, "Valora 下载")
        XCTAssertEqual(manifest["manifest_version"] as? Int, 3)
        XCTAssertEqual(manifest["background"] as? [String: Any] != nil, true)
        let permissions = manifest["permissions"] as? [String] ?? []
        XCTAssertTrue(permissions.contains("nativeMessaging"))
        XCTAssertTrue(permissions.contains("contextMenus"))
        XCTAssertTrue(permissions.contains("downloads"))
        XCTAssertFalse(permissions.contains("cookies"))
        XCTAssertEqual(manifest["host_permissions"] as? [String], ["http://*/*", "https://*/*"])
        XCTAssertFalse(manifest.keys.contains("content_scripts"))

        let key = try XCTUnwrap(manifest["key"] as? String)
        let der = try XCTUnwrap(Data(base64Encoded: key))
        let digest = SHA256.hash(data: der).map { String(format: "%02x", $0) }.joined()
        let id = String(digest.prefix(32).map { Character(UnicodeScalar(UInt8(97 + Int(String($0), radix: 16)!))) })
        XCTAssertEqual(id, ValoraChromeBridge.extensionID)
        XCTAssertNotEqual(id, "jfnchkplpoknchbbbnpgobnoolhdahmj", "Convoy's key/ID must not be reused")

        let background = try String(contentsOf: directory.appendingPathComponent("background.js"), encoding: .utf8)
        XCTAssertTrue(background.contains(ValoraChromeBridge.hostName))
        XCTAssertTrue(background.contains("PROTOCOL_VERSION = 1"))
        XCTAssertTrue(background.contains("onDeterminingFilename"))
        XCTAssertTrue(background.contains("suggest()"))
        XCTAssertTrue(background.contains("hostMissing"))
    }

    func testHTTPOnlyURLValidation() throws {
        XCTAssertEqual(try ChromeBridgeProtocol.validateDownloadURL("https://example.com/a.bin").host, "example.com")
        XCTAssertEqual(try ChromeBridgeProtocol.validateDownloadURL("http://example.com/a.bin").scheme, "http")
        for value in ["file:///tmp/a", "ftp://example.com/a", "data:text/plain,x",
                      "javascript:alert(1)", "https://user:pass@example.com/a",
                      "https:///missing-host", "https://example.com/\u{0000}"] {
            XCTAssertThrowsError(try ChromeBridgeProtocol.validateDownloadURL(value), value)
        }
    }

    func testEnvelopeRejectsOldConvoyAndWrongVersions() throws {
        var hello = ChromeBridgeProtocol.hello()
        try ChromeBridgeProtocol.validateEnvelope(hello)
        hello["app"] = "Convoy"
        XCTAssertThrowsError(try ChromeBridgeProtocol.validateEnvelope(hello))
        hello = ChromeBridgeProtocol.hello()
        hello["protocolVersion"] = 0
        XCTAssertThrowsError(try ChromeBridgeProtocol.validateEnvelope(hello))
        hello = ChromeBridgeProtocol.hello()
        hello["hostName"] = "io.github.thedynamicpunk.convoy.native"
        XCTAssertThrowsError(try ChromeBridgeProtocol.validateEnvelope(hello))
    }

    func testFramingRejectsHugeAndTruncatedMessages() throws {
        let data = Data("{\"type\":\"status\"}".utf8)
        let framed = try ChromeNativeFraming.encode(data)
        let decoded = try ChromeNativeFraming.decodeSingleJSON(framed)
        XCTAssertEqual(decoded["type"] as? String, "status")
        XCTAssertThrowsError(try ChromeNativeFraming.decodeSingleJSON(framed.dropLast()))
        var huge = Data()
        var length = UInt32(ValoraChromeBridge.maxMessageBytes + 1).littleEndian
        huge.append(Data(bytes: &length, count: 4))
        huge.append(Data(repeating: 0, count: Int(length)))
        XCTAssertThrowsError(try ChromeNativeFraming.decodeSingleJSON(huge))
    }
}

final class ChromeBridgeRegistrationTests: XCTestCase {
    private var root: URL!
    private var app: URL!
    private var host: URL!
    private var extensionDir: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        app = root.appendingPathComponent("Valora.app")
        host = app.appendingPathComponent("Contents/MacOS/\(ValoraChromeBridge.nativeHostExecutableName)")
        extensionDir = app.appendingPathComponent("Contents/Resources/ChromeExtension")
        try FileManager.default.createDirectory(at: host.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: extensionDir, withIntermediateDirectories: true)
        try Data("host".utf8).write(to: host)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: host.path)
        try Data("{}".utf8).write(to: extensionDir.appendingPathComponent("manifest.json"))
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: root)
    }

    private func registration(allowDevelopment: Bool = true) -> ChromeBridgeRegistration {
        ChromeBridgeRegistration(browserRoot: root.appendingPathComponent("browser/NativeMessagingHosts"),
                                 appBundleURL: app, hostExecutableURL: host,
                                 extensionDirectory: extensionDir,
                                 allowDevelopmentBundle: allowDevelopment)
    }

    func testRegistrationIsExplicitExactAndIsolated() throws {
        let reg = registration()
        XCTAssertEqual(reg.status(), .notSetUp)
        try reg.register()
        XCTAssertEqual(reg.status(), .ready)
        let object = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: reg.manifestURL)) as? [String: Any])
        XCTAssertEqual(object["name"] as? String, ValoraChromeBridge.hostName)
        XCTAssertEqual(object["path"] as? String, host.path)
        XCTAssertEqual(object["allowed_origins"] as? [String], ["chrome-extension://\(ValoraChromeBridge.extensionID)/"])
        let attributes = try FileManager.default.attributesOfItem(atPath: reg.manifestURL.path)
        XCTAssertEqual((attributes[.posixPermissions] as? NSNumber)?.intValue, 0o600)
        XCTAssertFalse(reg.manifestURL.path.contains("Convoy"))
    }

    func testExistingWrongManifestNeedsRepairWithoutWriting() throws {
        let reg = registration()
        try FileManager.default.createDirectory(at: reg.browserRoot, withIntermediateDirectories: true)
        try Data("[1,2,3]".utf8).write(to: reg.manifestURL)
        guard case .needsRepair = reg.status() else { return XCTFail("wrong manifest must need repair") }
        try reg.register()
        XCTAssertEqual(reg.status(), .ready)
    }

    func testTemporaryProductionBundleIsRejected() throws {
        let reg = registration(allowDevelopment: false)
        XCTAssertFalse(reg.isStableLocation)
        XCTAssertThrowsError(try reg.register()) { error in
            XCTAssertEqual(error as? ChromeBridgeRegistration.RegistrationError, .unstableLocation)
        }
    }

    func testHostOutsideBundleAndWorldWritableHostAreRejected() throws {
        let outside = root.appendingPathComponent("outside-host")
        try Data("host".utf8).write(to: outside)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: outside.path)
        let bad = ChromeBridgeRegistration(browserRoot: root.appendingPathComponent("browser"),
                                           appBundleURL: app, hostExecutableURL: outside,
                                           extensionDirectory: extensionDir, allowDevelopmentBundle: true)
        XCTAssertThrowsError(try bad.register())
        try FileManager.default.setAttributes([.posixPermissions: 0o777], ofItemAtPath: host.path)
        XCTAssertThrowsError(try registration().register())
    }
}

@MainActor
final class ChromeBridgeControllerTests: XCTestCase {
    private var root: URL!
    private var socketPath: String!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        socketPath = root.appendingPathComponent("bridge.sock").path
    }

    override func tearDownWithError() throws {
        unlink(socketPath)
        try? FileManager.default.removeItem(at: root)
    }

    private func requestAsync(_ object: [String: Any], path: String) async throws -> [String: Any]? {
        let data = try JSONSerialization.data(withJSONObject: object)
        let response = try await Task.detached { () -> Data in
            guard let fd = ChromeBridgeSocket.connect(path: path, timeout: 1) else { return Data() }
            defer { close(fd) }
            let framed = try ChromeNativeFraming.encode(data)
            _ = framed.withUnsafeBytes { send(fd, $0.baseAddress, $0.count, 0) }
            shutdown(fd, SHUT_WR)
            return ChromeBridgeSocket.readToEnd(fd: fd)
        }.value
        return try? ChromeNativeFraming.decodeSingleJSON(response)
    }

    func testHelloAndHTTPDownloadReachTheExistingService() async throws {
        let service = FakeDownloadService()
        let bridge = ChromeBridgeController(service: service, socketPath: socketPath,
                                            peerVerifier: { _ in .trusted })
        XCTAssertTrue(bridge.start())
        defer { bridge.stop() }
        let helloResponse = try await requestAsync(ChromeBridgeProtocol.hello(), path: socketPath)
        let hello = try XCTUnwrap(helloResponse)
        try ChromeBridgeProtocol.validateAppResponse(hello)
        XCTAssertEqual(hello["app"] as? String, "Valora")

        var download: [String: Any] = [
            "type": "download", "protocolVersion": 1, "app": "Valora",
            "hostName": ValoraChromeBridge.hostName,
            "appBundleIdentifier": ValoraChromeBridge.appBundleIdentifier,
            "url": "https://example.invalid/file.bin", "filename": "file.bin"
        ]
        let downloadResponse = try await requestAsync(download, path: socketPath)
        let response = try XCTUnwrap(downloadResponse)
        XCTAssertEqual(response["ok"] as? Bool, true)
        XCTAssertEqual(response["accepted"] as? Bool, true)
        XCTAssertEqual(response["protocolVersion"] as? Int, 1)
        XCTAssertEqual(response["app"] as? String, "Valora")
        XCTAssertEqual(service.items.count, 1)
        XCTAssertEqual(service.items.first?.sourceURL, "https://example.invalid/file.bin")

        download["url"] = "file:///tmp/secret"
        let rejectedData = try await requestAsync(download, path: socketPath)
        let rejected = try XCTUnwrap(rejectedData)
        XCTAssertEqual(rejected["ok"] as? Bool, false)
        XCTAssertEqual(service.items.count, 1)
    }

    func testOldIdentityAndPeerRejectionDoNotReachService() async throws {
        let service = FakeDownloadService()
        let bridge = ChromeBridgeController(service: service, socketPath: socketPath,
                                            peerVerifier: { _ in .trusted })
        XCTAssertTrue(bridge.start())
        defer { bridge.stop() }
        let old: [String: Any] = ["type": "hello", "protocolVersion": 1, "app": "Convoy",
                   "hostName": "io.github.thedynamicpunk.convoy.native",
                   "appBundleIdentifier": "io.github.thedynamicpunk.convoy"]
        let oldResponse = try await requestAsync(old, path: socketPath)
        let response = try XCTUnwrap(oldResponse)
        XCTAssertEqual(response["ok"] as? Bool, false)
        XCTAssertEqual(service.items.count, 0)

        bridge.stop()
        let rejecting = ChromeBridgeController(service: service, socketPath: socketPath,
                                               peerVerifier: { _ in .rejected("test peer") })
        XCTAssertTrue(rejecting.start())
        defer { rejecting.stop() }
        let rejectedResponse = try await requestAsync(ChromeBridgeProtocol.hello(), path: socketPath)
        XCTAssertNil(rejectedResponse)
    }

    func testStopClosesListenerAndLeavesNoSocket() async throws {
        let service = FakeDownloadService()
        let bridge = ChromeBridgeController(service: service, socketPath: socketPath,
                                            peerVerifier: { _ in .trusted })
        XCTAssertTrue(bridge.start())
        XCTAssertTrue(FileManager.default.fileExists(atPath: socketPath))
        bridge.stop()
        XCTAssertFalse(FileManager.default.fileExists(atPath: socketPath))
        let rejectedResponse = try await requestAsync(ChromeBridgeProtocol.hello(), path: socketPath)
        XCTAssertNil(rejectedResponse)
    }
}

@MainActor
final class ChromeBridgeSettingsModelTests: XCTestCase {
    func testSettingsStateMovesFromUnsetToReadyOnlyAfterExplicitInstall() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let app = root.appendingPathComponent("Valora.app")
        let host = app.appendingPathComponent("Contents/MacOS/\(ValoraChromeBridge.nativeHostExecutableName)")
        let extensionDir = app.appendingPathComponent("Contents/Resources/ChromeExtension")
        try FileManager.default.createDirectory(at: host.deletingLastPathComponent(), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: extensionDir, withIntermediateDirectories: true)
        try Data("host".utf8).write(to: host)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: host.path)
        try Data("{}".utf8).write(to: extensionDir.appendingPathComponent("manifest.json"))
        let registration = ChromeBridgeRegistration(
            browserRoot: root.appendingPathComponent("browser/NativeMessagingHosts"),
            appBundleURL: app, hostExecutableURL: host,
            extensionDirectory: extensionDir, allowDevelopmentBundle: true)
        let model = ChromeBridgeSettingsModel(registration: registration,
                                              bridgeListening: { false },
                                              lastHandshake: { nil })
        XCTAssertEqual(model.status, .notSetUp)
        model.installBridge()
        XCTAssertEqual(model.status, .ready)
        XCTAssertTrue(model.message?.contains("注册") == true)
        XCTAssertFalse(model.isBridgeListening)
    }
}
