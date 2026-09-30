import Darwin
import Foundation

/// The daemon's liveness signal: an exclusive `flock` on `<data dir>/run/daemon.lock`,
/// held for the whole life of the process and dropped by the kernel when it exits.
///
/// `SMAppService.status` cannot answer "has the daemon exited": it reads `.notRegistered`
/// the moment `unregister()` returns, while launchd may still be waiting for the process
/// to stop its VM. `abctl` probes the same lock.
enum DaemonLock {
    /// Whether a live daemon holds the lock at `url`.
    ///
    /// A missing file means no daemon: a clean exit removes it, and a killed daemon leaves
    /// a file whose lock the kernel has already released.
    static func isHeld(at url: URL) -> Bool {
        let descriptor = open(url.path, O_RDONLY)
        guard descriptor >= 0 else { return false }
        defer { close(descriptor) }
        if flock(descriptor, LOCK_EX | LOCK_NB) == 0 {
            flock(descriptor, LOCK_UN)
            return false
        }
        return errno == EWOULDBLOCK
    }

    /// Waits until no daemon holds the lock at `url`, polling every 200 ms.
    ///
    /// Returns `false` when `timeout` passes first.
    static func waitUntilReleased(at url: URL, timeout: Duration) async -> Bool {
        let clock = ContinuousClock()
        let deadline = clock.now + timeout
        while isHeld(at: url) {
            guard clock.now < deadline else { return false }
            try? await Task.sleep(for: .milliseconds(200))
        }
        return true
    }
}
