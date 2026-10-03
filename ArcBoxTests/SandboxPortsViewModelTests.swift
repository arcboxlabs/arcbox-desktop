import ArcBoxClient
import GRPCCore
import XCTest

@testable import ArcBox

@MainActor
final class SandboxPortsViewModelTests: XCTestCase {
    func testSnapshotReplacesMappingsAndEmptySnapshotClearsThem() async {
        let vm = SandboxesViewModel()
        let old = port(sandbox: 80, host: 8080)
        let replacement = port(sandbox: 443, host: 8443)
        vm.exposedPortsSandboxID = "sandbox"
        vm.exposedPortsLoadState = .loaded
        vm.exposedPorts["sandbox"] = [old]

        await vm.loadExposedPorts(for: "sandbox") { [replacement] }

        XCTAssertEqual(vm.exposedPorts["sandbox"], [replacement])
        XCTAssertEqual(vm.exposedPortsLoadState, .loaded)

        await vm.loadExposedPorts(for: "sandbox") { [] }

        XCTAssertEqual(vm.exposedPorts["sandbox"], [])
        XCTAssertEqual(vm.exposedPortsLoadState, .loaded)
    }

    func testStaleSandboxResponseCannotReplaceCurrentSandbox() async {
        let vm = SandboxesViewModel()
        let gate = PortFetchGate()
        let oldTask = Task {
            await vm.loadExposedPorts(for: "old") {
                try await gate.fetch()
            }
        }
        await gate.waitUntilStarted()

        let current = port(sandbox: 443, host: 8443)
        await vm.loadExposedPorts(for: "current") { [current] }
        gate.succeed([port(sandbox: 80, host: 8080)])
        await oldTask.value

        let cancelledTask = Task {
            await vm.loadExposedPorts(for: "cancelled") { [] }
        }
        cancelledTask.cancel()
        await cancelledTask.value

        XCTAssertEqual(vm.exposedPortsSandboxID, "current")
        XCTAssertEqual(vm.exposedPorts["current"], [current])
        XCTAssertNil(vm.exposedPorts["old"])
        XCTAssertNil(vm.exposedPorts["cancelled"])
        XCTAssertEqual(vm.exposedPortsLoadState, .loaded)
    }

    func testWaitsFailsAndRetriesInitialLoad() async {
        let vm = SandboxesViewModel()

        await vm.loadExposedPorts(for: "sandbox", client: nil)

        XCTAssertEqual(vm.exposedPortsSandboxID, "sandbox")
        XCTAssertEqual(vm.exposedPortsLoadState, .waiting)

        let gate = PortFetchGate()
        let failedTask = Task {
            await vm.loadExposedPorts(for: "sandbox") {
                try await gate.fetch()
            }
        }
        await gate.waitUntilStarted()
        XCTAssertEqual(vm.exposedPortsLoadState, .loading)
        XCTAssertTrue(vm.isLoadingExposedPorts)

        gate.fail(RPCError(code: .unavailable, message: "offline"))
        await failedTask.value

        XCTAssertEqual(
            vm.exposedPortsLoadState,
            .failed("Cannot reach ArcBox daemon. Is it running?")
        )
        XCTAssertNil(vm.exposedPortsRefreshError)
        XCTAssertFalse(vm.isLoadingExposedPorts)

        let mapping = port(sandbox: 80, host: 8080)
        await vm.loadExposedPorts(for: "sandbox") { [mapping] }

        XCTAssertEqual(vm.exposedPortsLoadState, .loaded)
        XCTAssertEqual(vm.exposedPorts["sandbox"], [mapping])
    }

    func testRefreshFailurePreservesLoadedMappings() async {
        let vm = SandboxesViewModel()
        let mapping = port(sandbox: 80, host: 8080)
        await vm.loadExposedPorts(for: "sandbox") { [mapping] }

        await vm.loadExposedPorts(for: "sandbox") {
            throw RPCError(code: .unavailable, message: "offline")
        }

        XCTAssertEqual(vm.exposedPortsLoadState, .loaded)
        XCTAssertEqual(vm.exposedPorts["sandbox"], [mapping])
        XCTAssertEqual(
            vm.exposedPortsRefreshError,
            "Cannot reach ArcBox daemon. Is it running?"
        )
        XCTAssertFalse(vm.isLoadingExposedPorts)
    }

    func testStaleRefreshCannotUndoLaterLocalRemoval() async {
        let vm = SandboxesViewModel()
        let mapping = port(sandbox: 80, host: 8080)
        await vm.loadExposedPorts(for: "sandbox") { [mapping] }

        let gate = PortFetchGate()
        let refreshTask = Task {
            await vm.loadExposedPorts(for: "sandbox") {
                try await gate.fetch()
            }
        }
        await gate.waitUntilStarted()

        vm.removeExposedPort(
            sandboxPort: mapping.sandboxPort,
            networkProtocol: mapping.networkProtocol,
            from: "sandbox"
        )
        gate.succeed([mapping])
        await refreshTask.value

        XCTAssertEqual(vm.exposedPorts["sandbox"], [])
        XCTAssertEqual(vm.exposedPortsLoadState, .loaded)
        XCTAssertFalse(vm.isLoadingExposedPorts)
    }

    private func port(
        sandbox: UInt32,
        host: UInt32,
        networkProtocol: String = "tcp"
    ) -> SandboxExposedPort {
        SandboxExposedPort(
            sandboxPort: sandbox,
            hostPort: host,
            networkProtocol: networkProtocol
        )
    }
}

@MainActor
private final class PortFetchGate {
    private(set) var started = false
    private var result: Result<[SandboxExposedPort], Error>?

    func fetch() async throws -> [SandboxExposedPort] {
        started = true
        while true {
            if let result {
                return try result.get()
            }
            await Task.yield()
        }
    }

    func waitUntilStarted() async {
        while !started {
            await Task.yield()
        }
    }

    func succeed(_ ports: [SandboxExposedPort]) {
        result = .success(ports)
    }

    func fail(_ error: Error) {
        result = .failure(error)
    }
}
