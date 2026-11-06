import Foundation

/// Writes exactly one Chrome native-messaging manifest. It is never called at
/// launch or by status refresh; the Settings action is the only production
/// caller. Tests inject an isolated browser root and a test bundle.
public struct ChromeBridgeRegistration: Sendable {
    public enum Status: Equatable, Sendable {
        case notSetUp
        case ready
        case needsRepair(String)
    }

    public enum RegistrationError: LocalizedError, Equatable {
        case unstableLocation
        case invalidHost(String)
        case invalidExtension
        case writeFailed(String)

        public var errorDescription: String? {
            switch self {
            case .unstableLocation: return "Valora 正从临时位置运行，不能注册为正式 Chrome 桥接"
            case .invalidHost(let reason): return "本地桥接程序不可用：\(reason)"
            case .invalidExtension: return "随包 Valora Chrome 扩展不完整"
            case .writeFailed(let reason): return "Chrome 桥接注册失败：\(reason)"
            }
        }
    }

    public let browserRoot: URL
    public let appBundleURL: URL
    public let hostExecutableURL: URL
    public let extensionDirectory: URL
    public let allowDevelopmentBundle: Bool

    public init(browserRoot: URL, appBundleURL: URL, hostExecutableURL: URL,
                extensionDirectory: URL, allowDevelopmentBundle: Bool = false) {
        self.browserRoot = browserRoot
        self.appBundleURL = appBundleURL
        self.hostExecutableURL = hostExecutableURL
        self.extensionDirectory = extensionDirectory
        self.allowDevelopmentBundle = allowDevelopmentBundle
    }

    public static func production(bundle: Bundle = .main,
                                  fileManager: FileManager = .default) -> ChromeBridgeRegistration {
        let support = fileManager.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        let browserRoot = support
            .appendingPathComponent("Google/Chrome/NativeMessagingHosts", isDirectory: true)
        let appBundle = bundle.bundleURL
        let host = appBundle.appendingPathComponent("Contents/MacOS/\(ValoraChromeBridge.nativeHostExecutableName)")
        let extensionURL = (bundle.resourceURL ?? appBundle.appendingPathComponent("Contents/Resources"))
            .appendingPathComponent(ValoraChromeBridge.extensionFolderName, isDirectory: true)
        return ChromeBridgeRegistration(browserRoot: browserRoot, appBundleURL: appBundle,
                                        hostExecutableURL: host, extensionDirectory: extensionURL)
    }

    public var manifestURL: URL {
        browserRoot.appendingPathComponent("\(ValoraChromeBridge.hostName).json")
    }

    public var hostBinaryIsValid: Bool {
        (try? validatedHostPath()) != nil
    }

    public func desiredManifest() throws -> [String: Any] {
        let host = try validatedHostPath()
        return [
            "name": ValoraChromeBridge.hostName,
            "description": "Valora Chrome Native Messaging Host",
            "path": host.path,
            "type": "stdio",
            "allowed_origins": ["chrome-extension://\(ValoraChromeBridge.extensionID)/"]
        ]
    }

    public func status() -> Status {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return .notSetUp }
        do {
            let desired = try desiredManifest()
            let data = try Data(contentsOf: manifestURL)
            guard let existing = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                  NSDictionary(dictionary: existing).isEqual(to: desired) else {
                return .needsRepair("Chrome 注册文件指向旧路径或不是 Valora")
            }
            return .ready
        } catch {
            return .needsRepair(error.localizedDescription)
        }
    }

    /// Explicit Settings action only. It rewrites only Valora's own
    /// `com.wangqing.valora.chrome.json` and never another app's host entry.
    public func register() throws {
        guard isStableLocation else { throw RegistrationError.unstableLocation }
        let host = try validatedHostPath()
        guard FileManager.default.fileExists(atPath: extensionDirectory.appendingPathComponent("manifest.json").path) else {
            throw RegistrationError.invalidExtension
        }
        _ = host
        let desired = try desiredManifest()
        do {
            try FileManager.default.createDirectory(at: browserRoot, withIntermediateDirectories: true,
                                                    attributes: [.posixPermissions: 0o700])
            let data = try JSONSerialization.data(withJSONObject: desired,
                                                  options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
            try data.write(to: manifestURL, options: .atomic)
            try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: manifestURL.path)
        } catch {
            throw RegistrationError.writeFailed(error.localizedDescription)
        }
    }

    public func removeOwnManifest() throws {
        guard FileManager.default.fileExists(atPath: manifestURL.path) else { return }
        try FileManager.default.removeItem(at: manifestURL)
    }

    public var isStableLocation: Bool {
        guard allowDevelopmentBundle == false else { return true }
        let path = appBundleURL.resolvingSymlinksInPath().path
        guard path.hasSuffix(".app"), path.contains("/Contents/") == false else { return false }
        let temporary = NSTemporaryDirectory()
        let prefixes = ["/tmp/", "/private/tmp/", "/private/var/folders/", temporary]
        return !prefixes.contains { path.hasPrefix($0) || path == String($0.dropLast()) }
    }

    private func validatedHostPath() throws -> URL {
        let canonical = hostExecutableURL.resolvingSymlinksInPath()
        let bundle = appBundleURL.resolvingSymlinksInPath().path
        let expectedPrefix = bundle + "/Contents/MacOS/"
        guard canonical.path.hasPrefix(expectedPrefix) else {
            throw RegistrationError.invalidHost("不在当前 Valora.app 的 Contents/MacOS 内")
        }
        guard FileManager.default.isExecutableFile(atPath: canonical.path) else {
            throw RegistrationError.invalidHost("文件不存在或不可执行")
        }
        guard let attributes = try? FileManager.default.attributesOfItem(atPath: canonical.path),
              let owner = attributes[.ownerAccountID] as? NSNumber,
              owner.intValue == Int(getuid()),
              let permissions = attributes[.posixPermissions] as? NSNumber,
              (permissions.intValue & 0o022) == 0 else {
            throw RegistrationError.invalidHost("所有者或权限不安全")
        }
        return canonical
    }
}
