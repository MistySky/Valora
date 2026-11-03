import Darwin
import Foundation

public enum ChromeBridgeSocket {
    /// NSTemporaryDirectory is per-user and short enough for sockaddr_un's
    /// 104-byte sun_path. The socket is created with umask 077 and chmod 0600.
    public static var currentPath: String {
        let path = NSTemporaryDirectory() + ValoraChromeBridge.socketFileName
        precondition(path.utf8.count < 104, "Valora Chrome bridge socket path is too long")
        return path
    }

    public static func makeAddress(path: String) -> (sockaddr_un, socklen_t) {
        var address = sockaddr_un()
        address.sun_family = sa_family_t(AF_UNIX)
        let bytes = Array(path.utf8CString)
        precondition(bytes.count <= 104, "Valora Chrome bridge socket path is too long")
        withUnsafeMutablePointer(to: &address.sun_path) { pointer in
            pointer.withMemoryRebound(to: CChar.self, capacity: 104) { output in
                for (index, byte) in bytes.enumerated() { output[index] = byte }
            }
        }
        let length = socklen_t(UInt8(MemoryLayout<UInt8>.size + MemoryLayout<sa_family_t>.size + bytes.count - 1))
        address.sun_len = UInt8(length)
        return (address, length)
    }

    public static func connect(path: String, timeout: TimeInterval = 2) -> Int32? {
        let fd = socket(AF_UNIX, SOCK_STREAM, 0)
        guard fd >= 0 else { return nil }
        let (address, length) = makeAddress(path: path)
        var mutable = address
        let result = withUnsafePointer(to: &mutable) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { Darwin.connect(fd, $0, length) }
        }
        guard result == 0 else { close(fd); return nil }
        var noSigPipe: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_NOSIGPIPE, &noSigPipe, socklen_t(MemoryLayout<Int32>.size))
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        setsockopt(fd, SOL_SOCKET, SO_SNDTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))
        return fd
    }

    public static func readToEnd(fd: Int32) -> Data {
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 16 * 1024)
        while true {
            let count = recv(fd, &buffer, buffer.count, 0)
            if count <= 0 { break }
            data.append(contentsOf: buffer[0..<count])
            if data.count > ValoraChromeBridge.maxMessageBytes { break }
        }
        return data
    }
}
