import Foundation

/// Fixed identity shared by the Valora app, its Chrome extension and the
/// browser-launched native-messaging helper. The extension ID is derived from
/// the public key committed in Resources/ChromeExtension/manifest.json; it is
/// deliberately not copied from Convoy.
public enum ValoraChromeBridge {
    public static let protocolVersion = 1
    public static let appName = "Valora"
    public static let appBundleIdentifier = "com.wangqing.valora"
    public static let hostName = "com.wangqing.valora.chrome"
    public static let nativeHostExecutableName = "ValoraNativeHost"
    public static let extensionID = "micfejmbldlgjepdfadhnoalmcbnpllb"
    public static let extensionFolderName = "ChromeExtension"
    public static let socketFileName = "valora-chrome-bridge.sock"
    public static let maxMessageBytes = 1_048_576
    public static let maxURLBytes = 16_384
}

public enum ChromeBridgeProtocolError: Error, LocalizedError, Equatable {
    case invalidMessage
    case unsupportedVersion(Int?)
    case wrongApp(String?)
    case wrongHost(String?)
    case invalidURL
    case invalidFilename
    case messageTooLarge
    case malformedFrame
    case wrongOrigin(String?)

    public var errorDescription: String? {
        switch self {
        case .invalidMessage: return "消息格式无效"
        case .unsupportedVersion(let version): return "不兼容的 Valora Chrome 桥接协议版本：\(version.map(String.init) ?? "未知")"
        case .wrongApp(let app): return "连接的不是 Valora：\(app ?? "未知程序")"
        case .wrongHost(let host): return "连接的不是 Valora 本地桥接：\(host ?? "未知宿主")"
        case .invalidURL: return "只接受 HTTP(S) 下载链接"
        case .invalidFilename: return "文件名无效"
        case .messageTooLarge: return "消息超过大小限制"
        case .malformedFrame: return "消息帧格式无效"
        case .wrongOrigin(let origin): return "Chrome 调用来源不是 Valora 扩展：\(origin ?? "缺失")"
        }
    }
}

public enum ChromeBridgeProtocol {
    /// The host sends this on a fresh socket. The app rejects the old Convoy
    /// host name/version rather than treating a shared Unix socket as proof.
    public static func hello(extensionID: String = ValoraChromeBridge.extensionID) -> [String: Any] {
        [
            "type": "hello",
            "protocolVersion": ValoraChromeBridge.protocolVersion,
            "app": ValoraChromeBridge.appName,
            "hostName": ValoraChromeBridge.hostName,
            "appBundleIdentifier": ValoraChromeBridge.appBundleIdentifier,
            "extensionID": extensionID
        ]
    }

    public static func helloResponse(appVersion: String) -> [String: Any] {
        [
            "ok": true,
            "protocolVersion": ValoraChromeBridge.protocolVersion,
            "app": ValoraChromeBridge.appName,
            "appBundleIdentifier": ValoraChromeBridge.appBundleIdentifier,
            "hostName": ValoraChromeBridge.hostName,
            "appVersion": appVersion
        ]
    }

    /// Validates the identity-bearing part of any request. The socket peer is
    /// additionally verified by code signature; this checks that the protocol
    /// and application identity match this Valora build.
    public static func validateEnvelope(_ object: [String: Any]) throws {
        guard let type = object["type"] as? String, !type.isEmpty else {
            throw ChromeBridgeProtocolError.invalidMessage
        }
        guard (object["protocolVersion"] as? Int) == ValoraChromeBridge.protocolVersion else {
            throw ChromeBridgeProtocolError.unsupportedVersion(object["protocolVersion"] as? Int)
        }
        guard type == "hello" || type == "status" else {
            // Every operational request is sent by the signed helper and
            // carries the same explicit identity fields.
            guard (object["app"] as? String) == ValoraChromeBridge.appName,
                  (object["hostName"] as? String) == ValoraChromeBridge.hostName,
                  (object["appBundleIdentifier"] as? String) == ValoraChromeBridge.appBundleIdentifier else {
                throw ChromeBridgeProtocolError.wrongApp(object["app"] as? String)
            }
            return
        }
        guard (object["app"] as? String) == ValoraChromeBridge.appName else {
            throw ChromeBridgeProtocolError.wrongApp(object["app"] as? String)
        }
        guard (object["hostName"] as? String) == ValoraChromeBridge.hostName else {
            throw ChromeBridgeProtocolError.wrongHost(object["hostName"] as? String)
        }
        guard (object["appBundleIdentifier"] as? String) == ValoraChromeBridge.appBundleIdentifier else {
            throw ChromeBridgeProtocolError.wrongApp(object["appBundleIdentifier"] as? String)
        }
        if let extensionID = object["extensionID"] as? String,
           extensionID != ValoraChromeBridge.extensionID {
            throw ChromeBridgeProtocolError.invalidMessage
        }
    }

    public static func validateAppResponse(_ object: [String: Any]) throws {
        guard (object["ok"] as? Bool) == true,
              (object["protocolVersion"] as? Int) == ValoraChromeBridge.protocolVersion,
              (object["app"] as? String) == ValoraChromeBridge.appName,
              (object["appBundleIdentifier"] as? String) == ValoraChromeBridge.appBundleIdentifier else {
            throw ChromeBridgeProtocolError.wrongApp(object["app"] as? String)
        }
    }

    public static func validateDownloadURL(_ raw: String) throws -> URL {
        guard raw.utf8.count <= ValoraChromeBridge.maxURLBytes,
              !raw.unicodeScalars.contains(where: { $0.value < 0x20 }),
              let url = URL(string: raw),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil,
              url.user == nil,
              url.password == nil else {
            throw ChromeBridgeProtocolError.invalidURL
        }
        return url
    }

    public static func validateFilename(_ raw: String?) throws -> String? {
        guard let raw, !raw.isEmpty else { return nil }
        guard raw.utf8.count <= 180,
              !raw.unicodeScalars.contains(where: { $0.value == 0 || $0.value < 0x20 }),
              !raw.contains("/"), raw != ".", raw != ".." else {
            throw ChromeBridgeProtocolError.invalidFilename
        }
        return raw
    }
}
