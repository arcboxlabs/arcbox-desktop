import AppKit
import SwiftUI
import XCTest

@testable import ArcBox
@testable import ArcBoxClient

/// Optional native renders for visual review. The fixtures do not connect to a runtime.
@MainActor
final class RuntimeStorageSnapshotTests: XCTestCase {
    func testRendersStorageFailureAndRecoveryForReview() throws {
        guard let directory = ProcessInfo.processInfo.environment["ARCBOX_STORAGE_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set ARCBOX_STORAGE_SNAPSHOT_DIR to render storage recovery for review.")
        }
        try FileManager.default.createDirectory(atPath: directory, withIntermediateDirectories: true)
        let daemon = DaemonManager()
        daemon.applySetupStatusSync(
            .with {
                $0.phase = .ready
                $0.vmRunning = true
                $0.storageHealth.observedAtUnixMs = 1_791_179_760_000
                $0.storageHealth.volumes = [
                    .with {
                        $0.role = .data
                        $0.state = .readOnly
                        $0.detail = "The data filesystem is mounted read-only after a write I/O failure."
                    },
                    .with {
                        $0.role = .metadata; $0.state = .mountedReadWrite
                    },
                ]
            })
        let recovery = RuntimeStorageRecoveryModel { _, _ in XCTFail("Rendering must not request recovery") }
        let root = VStack(spacing: 0) {
            RuntimeStorageBanner(onDetails: {})
            Form {
                RuntimeStorageDetails()
                RuntimeStorageRecoverySection()
            }
            .formStyle(.grouped)
        }
        .environment(daemon)
        .environment(recovery)
        .environment(ContainersViewModel())
        .environment(ImagesViewModel())
        .frame(width: 700, height: 700)
        .background(Color(nsColor: .windowBackgroundColor))

        for (name, appearance, protected) in [
            ("storage-light", NSAppearance.Name.aqua, false), ("storage-dark", .darkAqua, false),
            ("storage-protected-light", .aqua, true), ("storage-protected-dark", .darkAqua, true),
        ] {
            if protected {
                let progress = Arcbox_V1_StorageRecoveryProgress.with {
                    $0.operationID = "check-only"
                    $0.phase = .complete
                    $0.storageProtected = true
                }
                daemon.storageRecovery = progress
                daemon.vmRunning = false
                daemon.storageHealthIsCurrent = false
                recovery.reconcile(progress)
            }
            let hosting = NSHostingView(rootView: root)
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 700, height: 700),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: appearance)
            window.contentView = hosting
            defer { window.close() }
            for _ in 0..<3 {
                hosting.layoutSubtreeIfNeeded()
                hosting.displayIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
            }
            let bitmap = try XCTUnwrap(
                NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: 1400, pixelsHigh: 1400,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            bitmap.size = hosting.bounds.size
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: URL(fileURLWithPath: directory).appendingPathComponent("\(name).png"))
        }
    }
}
