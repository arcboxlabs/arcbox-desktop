import Darwin
import Foundation
import Testing

@testable import ArcBoxClient

struct DaemonLockTests {
    private func temporaryLockFile() -> URL {
        FileManager.default.temporaryDirectory
            .appendingPathComponent("daemon-lock-\(UUID().uuidString)")
    }

    @Test func missingFileMeansNoDaemon() {
        #expect(!DaemonLock.isHeld(at: temporaryLockFile()))
    }

    @Test func heldFlockMeansDaemonAlive() throws {
        let url = temporaryLockFile()
        #expect(FileManager.default.createFile(atPath: url.path, contents: nil))
        defer { try? FileManager.default.removeItem(at: url) }
        let holder = open(url.path, O_RDWR)
        #expect(holder >= 0)
        defer { close(holder) }

        #expect(flock(holder, LOCK_EX) == 0)
        #expect(DaemonLock.isHeld(at: url))

        // A killed daemon leaves the file behind with the lock already released.
        #expect(flock(holder, LOCK_UN) == 0)
        #expect(!DaemonLock.isHeld(at: url))
    }

    @Test func waitReturnsOnceTheHolderExits() async throws {
        let url = temporaryLockFile()
        #expect(FileManager.default.createFile(atPath: url.path, contents: nil))
        defer { try? FileManager.default.removeItem(at: url) }
        let holder = open(url.path, O_RDWR)
        #expect(holder >= 0)
        #expect(flock(holder, LOCK_EX) == 0)

        #expect(await DaemonLock.waitUntilReleased(at: url, timeout: .milliseconds(300)) == false)

        let release = Task {
            try await Task.sleep(for: .milliseconds(300))
            // Closing the descriptor drops the flock, as process exit does.
            close(holder)
        }
        #expect(await DaemonLock.waitUntilReleased(at: url, timeout: .seconds(5)))
        try await release.value
    }
}
