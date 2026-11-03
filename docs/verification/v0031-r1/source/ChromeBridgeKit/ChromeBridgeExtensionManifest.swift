import Foundation

/// Read-only facts used by tests and by the Settings diagnostics. The actual
/// extension manifest lives in Resources/ChromeExtension and is copied into
/// Valora.app/Contents/Resources/ChromeExtension by the packager.
public enum ChromeBridgeExtensionManifest {
    public static func load(from directory: URL) throws -> [String: Any] {
        let data = try Data(contentsOf: directory.appendingPathComponent("manifest.json"))
        guard let object = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw ChromeBridgeProtocolError.invalidMessage
        }
        return object
    }

    public static func validate(_ manifest: [String: Any]) throws {
        guard (manifest["manifest_version"] as? Int) == 3,
              (manifest["name"] as? String)?.contains("Valora") == true,
              let background = manifest["background"] as? [String: Any],
              (background["service_worker"] as? String) == "background.js",
              let permissions = manifest["permissions"] as? [String],
              permissions.contains("nativeMessaging"),
              permissions.contains("contextMenus"),
              permissions.contains("downloads"),
              !permissions.contains("cookies"),
              let hosts = manifest["host_permissions"] as? [String],
              hosts == ["http://*/*", "https://*/*"] else {
            throw ChromeBridgeProtocolError.invalidMessage
        }
        if let key = manifest["key"] as? String, key.isEmpty {
            throw ChromeBridgeProtocolError.invalidMessage
        }
    }
}
