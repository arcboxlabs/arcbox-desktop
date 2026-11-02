import AppKit
import DockerClient
import SwiftUI
import XCTest

@testable import ArcBox
@testable import ArcBoxClient

/// The default tab renders during startup, so it is where a readiness gate that opens
/// too early shows up (see AGENTS.md, "Default tab vs lazy tabs").
@MainActor
final class DefaultTabRuntimeReadinessTests: XCTestCase {
    /// The daemon reports host READY before the System VM boots. Containers, the default
    /// tab, must not ask Docker until the System runtime is READY, and must ask then.
    func testContainersWaitForTheSystemRuntimeNotTheHost() async throws {
        let daemon = DaemonManager()
        var status = Arcbox_V1_SetupStatus()
        status.phase = .ready
        status.systemRuntime = .with {
            $0.state = .vmStarting
            $0.reason = "Starting the System VM"
        }
        daemon.applySetupStatusSync(status)
        XCTAssertTrue(daemon.state.isRunning)

        let appVM = AppViewModel()
        XCTAssertEqual(appVM.currentNav, .containers, "the default tab moved; test that one instead")
        let containers = ContainersViewModel()
        let docker = DockerClient(socketPath: "/nonexistent/arcbox-tests/docker.sock")
        let host = OffscreenHost(
            ContentView()
                .environment(appVM)
                .environment(daemon)
                .environment(containers)
                .environment(ImagesViewModel())
                .environment(NetworksViewModel())
                .environment(VolumesViewModel())
                .environment(SandboxEventMonitor())
                .environment(\.dockerClient, docker)
        )
        // `settle()` alone holds the main actor, so the view's `.task` never runs inside
        // it; yield as well. An ungated load starts within about 0.1 s locally.
        func runUntil(_ deadline: Duration, while condition: () -> Bool) async throws {
            let end = ContinuousClock.now.advanced(by: deadline)
            while condition(), ContinuousClock.now < end {
                host.settle(passes: 1)
                try await Task.sleep(for: .milliseconds(10))
            }
        }
        try await runUntil(.seconds(1)) { containers.loadState == .waiting }
        XCTAssertEqual(containers.loadState, .waiting, "Containers asked Docker before the System runtime was ready")

        status.systemRuntime.state = .ready
        daemon.applySetupStatusSync(status)
        try await runUntil(.seconds(5)) { containers.loadState == .waiting }
        XCTAssertNotEqual(containers.loadState, .waiting, "Containers never loaded once the System runtime was ready")

        host.close()
        try await docker.shutdown()
    }
}
