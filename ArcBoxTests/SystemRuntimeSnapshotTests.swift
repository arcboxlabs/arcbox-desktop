import AppKit
import SwiftUI
import XCTest

@testable import ArcBox
@testable import ArcBoxClient

/// Optional native renders of the System runtime and software-emulation states for
/// visual review. The fixtures do not connect to a runtime.
@MainActor
final class SystemRuntimeSnapshotTests: XCTestCase {
    private static let appearances: [(String, NSAppearance.Name)] = [("light", .aqua), ("dark", .darkAqua)]

    /// Daemon states that have their own UI, as `SetupStatus` delivers them.
    private enum Fixture: String, CaseIterable {
        case emulationDownloading = "emulation-downloading"
        case emulationDownloadRetrying = "emulation-download-retrying"
        case emulationBooting = "emulation-booting"
        case runtimeFailed = "runtime-failed"
        case noVirtualization = "no-virtualization"
        case runtimeDisabled = "runtime-disabled"

        @MainActor func daemon() -> DaemonManager {
            let daemon = DaemonManager()
            var status = Arcbox_V1_SetupStatus()
            status.phase = .ready
            switch self {
            case .emulationDownloading:
                status.hardwareVirtualizationAvailable = false
                status.effectiveBackend = .qemu
                status.systemRuntime = .with {
                    $0.state = .downloading
                    $0.reason = "Downloading QEMU 0.1.0"
                    $0.download = .with {
                        $0.component = .qemu
                        $0.version = "0.1.0"
                        $0.stage = .transferring
                        $0.downloadedBytes = 3_250_000
                        $0.totalBytes = 5_930_315
                    }
                }
            case .emulationDownloadRetrying:
                status.hardwareVirtualizationAvailable = false
                status.effectiveBackend = .qemu
                status.systemRuntime = .with {
                    $0.state = .downloading
                    $0.reason = """
                        QEMU download interrupted: HTTP status 503 Service Unavailable. Retrying in 8 s; \
                        without network access, install it with `abctl qemu import <archive>`
                        """
                    // A first attempt the CDN refused: nothing on disk, size unknown.
                    $0.download = .with {
                        $0.component = .qemu
                        $0.version = "0.1.0"
                        $0.stage = .waitingToRetry
                    }
                }
            case .emulationBooting:
                status.hardwareVirtualizationAvailable = false
                status.effectiveBackend = .qemu
                status.systemRuntime = .with {
                    $0.state = .vmStarting
                    $0.reason = "Starting the System VM"
                }
            case .runtimeFailed:
                status.hardwareVirtualizationAvailable = true
                status.effectiveBackend = .vz
                status.systemRuntime = .with {
                    $0.state = .failed
                    $0.reason = "Failed to initialize System VM: the guest agent did not answer within 150 s"
                }
            case .noVirtualization:
                status.hardwareVirtualizationAvailable = false
                status.systemRuntime = .with {
                    $0.state = .failed
                    $0.reason = """
                        System VM cannot start: this Mac does not provide hardware virtualization (neither \
                        Virtualization.framework nor Hypervisor.framework is available, as inside a macOS \
                        virtual machine)
                        """
                }
            case .runtimeDisabled:
                status.hardwareVirtualizationAvailable = true
                status.effectiveBackend = .vz
                status.systemRuntime = .with { $0.state = .disabled }
            }
            daemon.applySetupStatusSync(status)
            return daemon
        }
    }

    func testRendersRuntimeStatesForReview() throws {
        guard let directory = ProcessInfo.processInfo.environment["ARCBOX_RUNTIME_SNAPSHOT_DIR"] else {
            throw XCTSkip("Set ARCBOX_RUNTIME_SNAPSHOT_DIR to render System runtime states for review.")
        }
        let output = URL(fileURLWithPath: directory)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)

        for fixture in Fixture.allCases {
            let daemon = fixture.daemon()
            let orchestrator = StartupOrchestrator(
                daemonManager: daemon, onClientsNeeded: { throw CancellationError() })
            orchestrator.phase = .completed
            for step in StartupStep.allCases {
                orchestrator.stepStatuses[step] = .completed
            }

            // Onboarding hosts the startup view in a 420×190 frame.
            try render(
                StartupProgressView(orchestrator: orchestrator, allowingAdministratorPrompt: true)
                    .frame(width: 420, height: 190),
                size: NSSize(width: 420, height: 190),
                name: "onboarding-\(fixture.rawValue)",
                in: output)

            // The main window's content column under its top banners.
            try render(
                VStack(spacing: 0) {
                    SoftwareEmulationBanner()
                    SystemRuntimeStatusView()
                }
                .environment(daemon)
                .environment(\.startupOrchestrator, orchestrator),
                size: NSSize(width: 720, height: 420),
                name: "main-\(fixture.rawValue)",
                in: output)
        }

        // The gate before the daemon is registered, for comparison with the daemon's report.
        let gated = StartupOrchestrator(daemonManager: DaemonManager(), onClientsNeeded: { throw CancellationError() })
        gated.phase = .virtualizationUnavailable
        try render(
            StartupProgressView(orchestrator: gated, allowingAdministratorPrompt: true).frame(width: 420, height: 190),
            size: NSSize(width: 420, height: 190),
            name: "onboarding-gate",
            in: output)

        let emulated = Fixture.emulationBooting.daemon()
        try render(
            MenuBarView()
                .environment(emulated)
                .environment(AppViewModel())
                .environment(ContainersViewModel())
                .environment(ImagesViewModel())
                .environment(NetworksViewModel())
                .environment(VolumesViewModel()),
            size: NSSize(width: 272, height: 380),
            name: "menubar-emulated",
            in: output)

        for (name, daemon) in [
            ("settings-no-virtualization", Fixture.noVirtualization.daemon()), ("settings-emulated", emulated),
        ] {
            try render(
                SystemSettingsView()
                    .environment(AppViewModel())
                    .environment(daemon)
                    .environment(SystemVmBackendModel()),
                size: NSSize(width: AppMetrics.settingsPaneWidth, height: 420),
                name: name,
                in: output)
        }

        // The sandbox list column where sandboxes cannot run, with the daemon's reasons.
        for (name, reason) in [
            (
                "sandboxes-no-virtualization",
                "this Mac does not provide hardware virtualization (neither Virtualization.framework nor "
                    + "Hypervisor.framework is available, as inside a macOS virtual machine)"
            ),
            ("sandboxes-chip", "nested virtualization requires Apple Silicon M3 or newer with macOS 15 or newer"),
        ] {
            try render(
                SandboxesUnsupportedView(reason: reason),
                size: NSSize(width: ColumnWidth.contentIdeal, height: 420),
                name: name,
                in: output)
        }
    }

    private func render(_ view: some View, size: NSSize, name: String, in directory: URL) throws {
        for (suffix, appearance) in Self.appearances {
            let hosting = NSHostingView(
                rootView:
                    view
                    .frame(width: size.width, height: size.height)
                    .background(Color(nsColor: .windowBackgroundColor)))
            let window = NSWindow(
                contentRect: NSRect(origin: NSPoint(x: -20_000, y: -20_000), size: size),
                styleMask: [.borderless], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            window.appearance = NSAppearance(named: appearance)
            window.contentView = hosting
            defer { window.close() }
            for _ in 0..<5 {
                hosting.layoutSubtreeIfNeeded()
                hosting.displayIfNeeded()
                RunLoop.main.run(until: Date(timeIntervalSinceNow: 0.02))
            }
            let bitmap = try XCTUnwrap(
                NSBitmapImageRep(
                    bitmapDataPlanes: nil, pixelsWide: Int(size.width) * 2, pixelsHigh: Int(size.height) * 2,
                    bitsPerSample: 8, samplesPerPixel: 4, hasAlpha: true, isPlanar: false,
                    colorSpaceName: .deviceRGB, bytesPerRow: 0, bitsPerPixel: 0))
            bitmap.size = hosting.bounds.size
            hosting.cacheDisplay(in: hosting.bounds, to: bitmap)
            let data = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
            try data.write(to: directory.appendingPathComponent("\(name)-\(suffix).png"))
        }
    }
}
