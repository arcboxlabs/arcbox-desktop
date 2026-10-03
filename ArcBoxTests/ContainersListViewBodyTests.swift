import AppKit
import DockerClient
import SwiftUI
import XCTest

@testable import ArcBox
@testable import ArcBoxClient

/// Pins what invalidates `ContainersListView.body`. The SwiftUI wrapper owns
/// the toolbar and the `NSViewControllerRepresentable`, so every evaluation
/// rebuilds both; container state changes must not reach it.
@MainActor
final class ContainersListViewBodyTests: XCTestCase {
    private var window: NSWindow?

    override func tearDown() {
        window?.close()
        window = nil
        super.tearDown()
    }

    func testContainerChangesDoNotReevaluateBody() async throws {
        let viewModel = ContainersViewModel()
        viewModel.loadState = .loaded
        viewModel.containers = (0..<5).map { index in
            ContainerViewModel(
                id: "c\(index)",
                name: "c\(index)",
                image: "nginx:latest",
                state: .running,
                ports: [],
                createdAt: .distantPast,
                composeProject: nil,
                composeService: nil,
                labels: [:],
                cpuPercent: 0,
                memoryMB: 0,
                memoryLimitMB: 0
            )
        }
        let daemonManager = DaemonManager()
        daemonManager.state = .running
        daemonManager.setupPhase = .ready
        let docker = DockerClient(socketPath: "/nonexistent/arcbox-tests/docker.sock")

        let hostingView = NSHostingView(
            rootView: ContainersListView()
                .environment(viewModel)
                .environment(daemonManager)
                .environment(\.dockerClient, docker)
        )
        let window = NSWindow(
            contentRect: NSRect(x: 0, y: 0, width: 700, height: 600),
            styleMask: [.titled],
            backing: .buffered,
            defer: false
        )
        window.isReleasedWhenClosed = false
        window.contentView = hostingView
        self.window = window
        hostingView.layoutSubtreeIfNeeded()

        try await waitUntil { ContainersListView.bodyEvaluations > 0 }
        // Let the `.task` load against the unreachable socket fail and settle.
        try await Task.sleep(for: .milliseconds(300))
        let settled = ContainersListView.bodyEvaluations

        for iteration in 0..<20 {
            viewModel.setContainerRunningState("c\(iteration % 5)", isRunning: iteration.isMultiple(of: 2))
            try await Task.sleep(for: .milliseconds(5))
        }
        try await Task.sleep(for: .milliseconds(50))
        let afterContainerChanges = ContainersListView.bodyEvaluations
        print("PERF ContainersListView.body evaluations for 20 container mutations: \(afterContainerChanges - settled)")
        XCTAssertEqual(afterContainerChanges, settled, "container mutations re-evaluated the wrapper body")

        daemonManager.dnsResolverInstalled.toggle()
        try await waitUntil { ContainersListView.bodyEvaluations > afterContainerChanges }
        XCTAssertEqual(ContainersListView.bodyEvaluations, afterContainerChanges + 1)

        window.close()
        try await docker.shutdown()
    }

    private func waitUntil(
        file: StaticString = #filePath,
        line: UInt = #line,
        _ condition: @escaping @MainActor () -> Bool
    ) async throws {
        let clock = ContinuousClock()
        let deadline = clock.now.advanced(by: .seconds(3))
        while !condition(), clock.now < deadline {
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertTrue(condition(), "Timed out waiting for a SwiftUI update", file: file, line: line)
    }
}
