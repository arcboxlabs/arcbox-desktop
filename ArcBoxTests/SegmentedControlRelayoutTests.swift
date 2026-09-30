import AppKit
import ArcBoxClient
import SwiftUI
import XCTest

@testable import ArcBox

/// Pins the fix for the ARCBOX-DESKTOP-SWIFT-T hang cluster (-30, -32, -2R,
/// -4V share its stack): a segmented `Picker` is SwiftUI's
/// `SystemSegmentedControl`, an `NSSegmentedControl` whose every `sizeThatFits`
/// re-runs its own inner view graph. Placed in a body that also renders a hot
/// stream (log batches, mapping refreshes), each update paid that
/// re-measurement — ~1.3 ms per layout pass on this machine, seconds once
/// bodies and updates multiply.
///
/// The fix keeps the segmented pickers in leaf views that observe none of the
/// hot state. These tests hold the two properties the fix rests on: the hot
/// update never evaluates the leaf's body, and the picker still binds both ways.
@MainActor
final class SegmentedControlRelayoutTests: XCTestCase {
    private static let hotUpdates = 200

    // MARK: - Which views create an NSSegmentedControl

    func testDetailTabPickerCreatesNoSegmentedControl() throws {
        let host = OffscreenHost(DetailTabPickerHarness(model: DetailTabHarnessModel()))
        defer { host.close() }

        let toolbar = try XCTUnwrap(host.window.toolbar)
        XCTAssertEqual(toolbar.items.count, 1)
        // On macOS 26 the `accessibilityRepresentation { Picker(.segmented) }`
        // synthesizes accessibility nodes only; no platform view is created,
        // so the toolbar tab bar is not a host for the hang signature.
        XCTAssertEqual(host.segmentedControlClassNames(), [])
    }

    func testLogsStreamFilterIsAnAppKitSegmentedControl() {
        let host = OffscreenHost(ContainerLogsTab(container: Self.container, model: ContainerLogsModel()))
        defer { host.close() }

        XCTAssertEqual(host.segmentedControls().count, 1)
        XCTAssertTrue(
            host.segmentedControlClassNames().contains { $0.contains("SystemSegmentedControl") },
            "\(host.segmentedControlClassNames())"
        )
    }

    func testSandboxPortsProtocolPickerIsAnAppKitSegmentedControl() {
        let fixture = SandboxPortsFixture()
        let host = OffscreenHost(fixture.tab)
        defer { host.close() }

        XCTAssertEqual(host.segmentedControls().count, 1)
    }

    // MARK: - Hot updates stay out of the pickers' bodies

    func testLogAppendsDoNotReevaluateTheLogsToolbar() {
        let model = ContainerLogsModel()
        let host = OffscreenHost(ContainerLogsTab(container: Self.container, model: model))
        defer { host.close() }
        // `startStreaming` has run by now (no Docker client, so it only reset
        // the model); seed enough lines for the list to be showing.
        model.isLoading = false
        model.logEntries = (0..<300).map { Self.logEntry($0) }
        host.settle()

        BodyEvaluationCounter.reset()
        var next = model.logEntries.count
        let elapsed = host.measureUpdates(count: Self.hotUpdates) {
            next += 1
            model.logEntries.append(Self.logEntry(next))
        }

        XCTAssertEqual(BodyEvaluationCounter.count(of: ContainerLogsContent.self), Self.hotUpdates)
        XCTAssertEqual(BodyEvaluationCounter.count(of: ContainerLogsToolbar.self), 0)
        // 26 ms locally for the split view against 280 ms for the previous
        // single body (with the picker; 26 ms without). Generous so CI passes;
        // the evaluation counts above are the exact gate.
        XCTAssertLessThan(elapsed, .seconds(1), "\(Self.hotUpdates) log appends took \(elapsed)")
        print("SegmentedControlRelayoutTests: \(Self.hotUpdates) log appends took \(elapsed)")
    }

    func testMappingRefreshesDoNotReevaluateThePortsToolbar() {
        let fixture = SandboxPortsFixture()
        let host = OffscreenHost(fixture.tab)
        defer { host.close() }
        fixture.showLoadedMappings([Self.port(8080)])
        host.settle()

        BodyEvaluationCounter.reset()
        var next: UInt32 = 8080
        let elapsed = host.measureUpdates(count: Self.hotUpdates) {
            next += 1
            fixture.vm.exposedPorts[fixture.sandbox.id] = [Self.port(next)]
        }

        XCTAssertEqual(BodyEvaluationCounter.count(of: SandboxPortsContent.self), Self.hotUpdates)
        XCTAssertEqual(BodyEvaluationCounter.count(of: SandboxPortsToolbar.self), 0)
        XCTAssertLessThan(elapsed, .seconds(1), "\(Self.hotUpdates) mapping refreshes took \(elapsed)")
        print("SegmentedControlRelayoutTests: \(Self.hotUpdates) mapping refreshes took \(elapsed)")
    }

    // MARK: - The pickers still bind both ways

    func testLogsStreamFilterRoundTripsThroughTheBinding() throws {
        let model = ContainerLogsModel()
        let host = OffscreenHost(ContainerLogsTab(container: Self.container, model: model))
        defer { host.close() }
        let control = try XCTUnwrap(host.segmentedControls().first)
        XCTAssertEqual(control.segmentCount, LogStreamFilter.allCases.count)
        XCTAssertEqual(control.selectedSegment, 0)

        model.streamFilter = .stderr
        host.settle()
        XCTAssertEqual(control.selectedSegment, 2)

        control.selectedSegment = 1
        _ = control.sendAction(control.action, to: control.target)
        host.settle()
        XCTAssertEqual(model.streamFilter, .stdout)
    }

    func testPortsProtocolPickerRoundTripsThroughTheBinding() throws {
        let fixture = SandboxPortsFixture()
        let host = OffscreenHost(fixture.tab)
        defer { host.close() }
        let control = try XCTUnwrap(host.segmentedControls().first)
        XCTAssertEqual(control.selectedSegment, 0, "TCP is the default")

        control.selectedSegment = 1
        _ = control.sendAction(control.action, to: control.target)
        host.settle()
        // Re-evaluate the toolbar from state it observes: a picker whose
        // binding rejected the click would snap back to TCP here.
        fixture.vm.exposedPortsLoadState = .loading
        host.settle()
        fixture.vm.exposedPortsLoadState = .loaded
        host.settle()
        XCTAssertEqual(control.selectedSegment, 1)
    }

    // MARK: - Detail tab bar accessibility

    func testDetailTabPickerExposesEveryTabWithExactlyOneSelected() throws {
        let model = DetailTabHarnessModel()
        let host = OffscreenHost(DetailTabPickerHarness(model: model))
        defer { host.close() }
        let itemView = try XCTUnwrap(host.window.toolbar?.items.first?.view)

        func tabButtons() -> [OffscreenHost.AccessibilityNode] {
            host.accessibilityTree(from: itemView).filter { $0.subrole == "AXTabButton" }
        }
        print("SegmentedControlRelayoutTests: detail tab bar AX tree\n\(host.accessibilityDump(from: itemView))")

        var buttons = tabButtons()
        XCTAssertEqual(buttons.map(\.label), ContainerDetailTab.allCases.map(\.rawValue))
        XCTAssertEqual(buttons.map(\.role), Array(repeating: "AXRadioButton", count: buttons.count))
        XCTAssertEqual(buttons.filter(\.isSelected).map(\.label), ["Info"])

        model.tab = .terminal
        host.settle()
        buttons = tabButtons()
        XCTAssertEqual(buttons.filter(\.isSelected).map(\.label), ["Terminal"])

        try XCTUnwrap(buttons.first { $0.label == "Files" }).press()
        host.settle()
        XCTAssertEqual(model.tab, .files)
        XCTAssertEqual(tabButtons().filter(\.isSelected).map(\.label), ["Files"])
    }

    // MARK: - Fixtures

    private static let container = ContainerViewModel(
        id: "container-1",
        name: "web",
        image: "nginx:latest",
        state: .running,
        ports: [],
        createdAt: Date(),
        composeProject: nil,
        composeService: nil,
        labels: [:],
        cpuPercent: 0,
        memoryMB: 0,
        memoryLimitMB: 0
    )

    private static func logEntry(_ index: Int) -> LogEntry {
        LogEntry(timestamp: nil, stream: .stdout, message: "line \(index)")
    }

    private static func port(_ sandboxPort: UInt32) -> SandboxExposedPort {
        SandboxExposedPort(sandboxPort: sandboxPort, hostPort: 30_000 + sandboxPort, networkProtocol: "tcp")
    }
}

@Observable
private final class DetailTabHarnessModel {
    var tick = 0
    var tab: ContainerDetailTab = .info
}

/// Mirrors `ContainerDetailView`: a body that reads hot state and installs
/// `DetailTabPicker` in the window toolbar.
private struct DetailTabPickerHarness: View {
    let model: DetailTabHarnessModel

    var body: some View {
        @Bindable var model = model
        VStack {
            Text("tick \(model.tick)")
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .toolbar {
            DetailTabPicker(selection: $model.tab)
        }
    }
}

/// A `SandboxPortsTab` with the environment it reads, driven through `vm`.
@MainActor
private struct SandboxPortsFixture {
    let vm = SandboxesViewModel()
    let daemonManager = DaemonManager()
    let sandbox: SandboxViewModel

    init() {
        var summary = Arcbox_Sandbox_V1_SandboxSummary()
        summary.id = "sandbox-1"
        sandbox = SandboxViewModel(from: summary)
        vm.sandboxes = [sandbox]
        vm.selectedID = sandbox.id
    }

    var tab: some View {
        SandboxPortsTab(sandbox: sandbox)
            .environment(vm)
            .environment(daemonManager)
    }

    /// Puts the tab into its loaded state with `mappings` listed.
    func showLoadedMappings(_ mappings: [SandboxExposedPort]) {
        vm.exposedPortsSandboxID = sandbox.id
        vm.exposedPorts[sandbox.id] = mappings
        vm.exposedPortsLoadState = .loaded
    }
}
