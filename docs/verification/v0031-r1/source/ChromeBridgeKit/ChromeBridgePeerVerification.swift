import Darwin
import Foundation
import MachO
import Security
import os

/// Valora's narrow adaptation of Convoy's socket peer verification
/// (TheDynamicPunk/Convoy, GPL-3.0, revision 007a2097). Both sides of the
/// Valora bridge prove they are the sibling binary in this exact app bundle;
/// a process merely running as the same user is not enough.
public enum ChromePeerVerification {
    private static let logger = Logger(subsystem: "com.wangqing.valora", category: "ChromeBridgePeer")

    public enum Counterpart: Sendable {
        case app
        case nativeMessagingHost

        var executableName: String {
            switch self {
            case .app: return "Valora"
            case .nativeMessagingHost: return ValoraChromeBridge.nativeHostExecutableName
            }
        }
    }

    public enum Outcome: Sendable {
        case trusted
        case rejected(String)
        public var isTrusted: Bool { if case .trusted = self { true } else { false } }
        public var rejectionReason: String? { if case .rejected(let reason) = self { reason } else { nil } }
    }

    public static func verifyPeer(onSocket fd: Int32, expecting counterpart: Counterpart) -> Outcome {
        guard let counterpartURL = counterpartURL(for: counterpart) else {
            return reject("无法定位本进程可执行文件，不能核验对端")
        }
        guard FileManager.default.fileExists(atPath: counterpartURL.path) else {
            return reject("缺少对端可执行文件：\(counterpartURL.path)")
        }
        let requirement: SecRequirement
        switch designatedRequirement(ofBinaryAt: counterpartURL) {
        case .success(let value): requirement = value
        case .failure(let reason): return reject(reason)
        }
        guard let auditToken = peerAuditToken(fd) else {
            return reject("无法读取 socket 对端的 audit token")
        }
        var guestCode: SecCode?
        let attributes = [kSecGuestAttributeAudit as String: auditToken] as CFDictionary
        let copyStatus = SecCodeCopyGuestWithAttributes(nil, attributes, SecCSFlags(), &guestCode)
        guard copyStatus == errSecSuccess, let code = guestCode else {
            return reject("无法取得对端代码对象（status \(copyStatus)）")
        }
        let validity = SecCodeCheckValidity(code, SecCSFlags(), requirement)
        guard validity == errSecSuccess else {
            return reject("对端 \(path(of: code)) 与同包 \(counterpartURL.path) 不匹配（status \(validity)）")
        }
        return .trusted
    }

    public static func ownExecutableURL() -> URL? {
        var size: UInt32 = 0
        _ = _NSGetExecutablePath(nil, &size)
        guard size > 0 else { return nil }
        var buffer = [CChar](repeating: 0, count: Int(size))
        guard _NSGetExecutablePath(&buffer, &size) == 0 else { return nil }
        guard let resolved = realpath(buffer, nil) else { return nil }
        defer { free(resolved) }
        return URL(fileURLWithPath: String(cString: resolved))
    }

    private enum RequirementResult {
        case success(SecRequirement)
        case failure(String)
    }

    private static func designatedRequirement(ofBinaryAt url: URL) -> RequirementResult {
        var staticCode: SecStaticCode?
        let create = SecStaticCodeCreateWithPath(url as CFURL, SecCSFlags(), &staticCode)
        guard create == errSecSuccess, let code = staticCode else {
            return .failure("无法读取对端签名：\(url.path)（status \(create)）")
        }
        var requirement: SecRequirement?
        let copy = SecCodeCopyDesignatedRequirement(code, SecCSFlags(), &requirement)
        guard copy == errSecSuccess, let value = requirement else {
            return .failure("对端没有 designated requirement：\(url.path)（status \(copy)）")
        }
        return .success(value)
    }

    private static func counterpartURL(for counterpart: Counterpart) -> URL? {
        ownExecutableURL()?.deletingLastPathComponent()
            .appendingPathComponent(counterpart.executableName)
    }

    private static func path(of code: SecCode) -> String {
        var staticCode: SecStaticCode?
        guard SecCodeCopyStaticCode(code, SecCSFlags(), &staticCode) == errSecSuccess,
              let sc = staticCode else { return "<unknown>" }
        var url: CFURL?
        guard SecCodeCopyPath(sc, SecCSFlags(), &url) == errSecSuccess, let path = url as URL? else {
            return "<unknown>"
        }
        return path.path
    }

    private static func peerAuditToken(_ fd: Int32) -> Data? {
        let size = MemoryLayout<audit_token_t>.size
        var buffer = [UInt8](repeating: 0, count: size)
        var length = socklen_t(size)
        let result = buffer.withUnsafeMutableBytes {
            getsockopt(fd, SOL_LOCAL, LOCAL_PEERTOKEN, $0.baseAddress, &length)
        }
        guard result == 0, length == socklen_t(size) else { return nil }
        return Data(buffer)
    }

    private static func reject(_ reason: String) -> Outcome {
        let collapsed = reason.replacingOccurrences(of: "\n", with: " ")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        logger.error("Chrome bridge peer rejected: \(collapsed, privacy: .public)")
        return .rejected(collapsed)
    }
}
