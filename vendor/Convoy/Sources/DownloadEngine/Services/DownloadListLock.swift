import Foundation

/// Lets only one running copy of the app own the download list. The kernel
/// releases a `flock` when its process exits, so it never goes stale.
///
/// Ownership is explicit: a lock that cannot be created or acquired is
/// unavailable, not "owned". Callers must not load, save, clean or start
/// downloads unless `isOwned` is true.
final class DownloadListLock {
    enum State: Equatable {
        case owned
        case heldElsewhere
        case unavailable
    }

    let state: State
    let unavailableReason: String?
    private let descriptor: Int32

    /// True only when another process owns the same list. A missing lock file
    /// or any open/flock error is `unavailable`, never `heldElsewhere`.
    var isHeldElsewhere: Bool { state == .heldElsewhere }
    var isOwned: Bool { state == .owned }
    var isUnavailable: Bool { state == .unavailable }

    init(beside listURL: URL) {
        let folder = listURL.deletingLastPathComponent()
        let path = listURL.deletingPathExtension().appendingPathExtension("lock").path
        do {
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        } catch {
            self.state = .unavailable
            self.unavailableReason = "could not create download storage folder: \(error.localizedDescription)"
            self.descriptor = -1
            return
        }

        let fd = open(path, O_RDWR | O_CREAT | O_CLOEXEC, 0o600)
        guard fd >= 0 else {
            self.state = .unavailable
            self.unavailableReason = "could not open download list lock: \(String(cString: strerror(errno)))"
            self.descriptor = -1
            return
        }

        if flock(fd, LOCK_EX | LOCK_NB) == 0 {
            self.state = .owned
            self.unavailableReason = nil
            self.descriptor = fd
        } else if errno == EWOULDBLOCK {
            close(fd)
            self.state = .heldElsewhere
            self.unavailableReason = "another running copy owns the download list"
            self.descriptor = -1
        } else {
            let reason = String(cString: strerror(errno))
            close(fd)
            self.state = .unavailable
            self.unavailableReason = "could not acquire download list lock: \(reason)"
            self.descriptor = -1
        }
    }

    deinit {
        if descriptor >= 0 { close(descriptor) }
    }
}
