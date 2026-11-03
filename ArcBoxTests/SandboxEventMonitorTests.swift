import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2TransportServices
import GRPCProtobuf
import SwiftProtobuf
import Synchronization
import XCTest

@testable import ArcBox
@testable import ArcBoxClient

/// Every accepted sandbox event subscription resyncs the sandbox list, so how the
/// monitor resubscribes decides how often the Sandboxes tab reloads. These run the
/// monitor against a gRPC server on a Unix socket that answers the way the daemon does.
@MainActor
final class SandboxEventMonitorTests: XCTestCase {
    /// A subscription the daemon accepts and ends at once, with an error that does not say
    /// the failure lasts, backs off. Resetting the backoff on every accepted subscription
    /// resubscribed and resynced every 2 s for as long as the app ran.
    func testASubscriptionTheDaemonEndsAtOnceBacksOff() async throws {
        let daemon = try await SandboxDaemon(events: .acceptThenFail)
        let first = expectation(forNotification: .sandboxChanged, object: nil)
        first.assertForOverFulfill = false
        daemon.monitor.follow(daemon.manager, client: daemon.client, machineID: "default")
        await fulfillment(of: [first], timeout: 10)

        // Backing off, the next two resyncs come 2 s and 6 s after the first; a 2 s
        // retry brings both within 4 s.
        let twoMore = expectation(forNotification: .sandboxChanged, object: nil)
        twoMore.expectedFulfillmentCount = 2
        twoMore.isInverted = true
        await fulfillment(of: [twoMore], timeout: 5)

        await daemon.close()
    }

    /// A backend that cannot run sandboxes refuses with `NESTED_VIRT_UNSUPPORTED`, which
    /// nothing changes until the effective backend does. arcbox writes the response
    /// headers before the trailers that carry the refusal, so grpc-swift accepts the
    /// subscription and the refusal ends its stream.
    func testAHostThatCannotRunSandboxesWaitsForAnotherBackend() async throws {
        let daemon = try await SandboxDaemon(events: .acceptThenRefuse)
        let accepted = expectation(forNotification: .sandboxChanged, object: nil)
        accepted.assertForOverFulfill = false
        daemon.monitor.follow(daemon.manager, client: daemon.client, machineID: "default")
        await fulfillment(of: [accepted], timeout: 10)

        let retry = expectation(forNotification: .sandboxChanged, object: nil)
        retry.isInverted = true
        // A retry would come 2 s after the first subscription.
        await fulfillment(of: [retry], timeout: 3)
        XCTAssertEqual(daemon.subscriptions, 1)

        daemon.status.phase = .degraded
        daemon.manager.applySetupStatusSync(daemon.status)
        daemon.monitor.follow(daemon.manager, client: daemon.client, machineID: "default")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(daemon.subscriptions, 1, "resubscribed though the backend did not change")

        daemon.status.effectiveBackend = .vz
        daemon.manager.applySetupStatusSync(daemon.status)
        daemon.monitor.follow(daemon.manager, client: daemon.client, machineID: "default")
        let end = ContinuousClock.now.advanced(by: .seconds(5))
        while daemon.subscriptions < 2, ContinuousClock.now < end {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(daemon.subscriptions, 2, "did not resubscribe once the backend changed")

        await daemon.close()
    }

    /// The System VM runs the sandboxes. Subscribing while it starts fails, and every
    /// startup logged a reconnect warning per attempt.
    func testWaitsForTheSystemVM() async throws {
        let daemon = try await SandboxDaemon(events: .acceptThenRefuse)
        daemon.status.systemRuntime.state = .vmStarting
        daemon.manager.applySetupStatusSync(daemon.status)
        daemon.monitor.follow(daemon.manager, client: daemon.client, machineID: "default")
        try await Task.sleep(for: .milliseconds(500))
        XCTAssertEqual(daemon.subscriptions, 0, "subscribed before the System VM was up")

        daemon.status.systemRuntime.state = .ready
        daemon.manager.applySetupStatusSync(daemon.status)
        daemon.monitor.follow(daemon.manager, client: daemon.client, machineID: "default")
        let end = ContinuousClock.now.advanced(by: .seconds(5))
        while daemon.subscriptions < 1, ContinuousClock.now < end {
            try await Task.sleep(for: .milliseconds(50))
        }
        XCTAssertEqual(daemon.subscriptions, 1, "did not subscribe once the System VM was up")

        await daemon.close()
    }
}

/// The sandbox list on a Mac that cannot run sandboxes, against the same daemon.
@MainActor
final class SandboxesListLoadTests: XCTestCase {
    private static let reason =
        "this Mac does not provide hardware virtualization (neither Virtualization.framework nor "
        + "Hypervisor.framework is available, as inside a macOS virtual machine)"

    /// arcbox v0.11.2 relays the guest's refusal, whose message names a fix that does not
    /// apply here; later daemons refuse on the host with the reason. Either way the daemon's
    /// capabilities give the reason, and the list shows it instead of a retry that cannot help.
    func testAHostThatCannotRunSandboxesShowsWhy() async throws {
        let daemon = try await SandboxDaemon(events: .acceptThenRefuse)
        let vm = SandboxesViewModel()
        let refusals = try [SandboxService.guestRefusal(), SandboxService.hostRefusal(reason: Self.reason)]
        for refusal in refusals {
            daemon.service.listRefusal.withLock { $0 = refusal }
            daemon.service.nestedVirt.withLock { $0 = .with { $0.reason = Self.reason } }
            await vm.loadSandboxes(client: daemon.client)
            XCTAssertEqual(vm.unsupportedReason, Self.reason)
            XCTAssertEqual(vm.loadState, .failed(Self.reason))

            // Another backend that can run them lists them again.
            daemon.service.listRefusal.withLock { $0 = nil }
            daemon.service.nestedVirt.withLock { $0 = .with { $0.supported = true } }
            await vm.loadSandboxes(client: daemon.client)
            XCTAssertNil(vm.unsupportedReason)
            XCTAssertEqual(vm.loadState, .loaded)
        }

        await daemon.close()
    }

    /// `FAILED_PRECONDITION` also covers transient states. On a host that can run
    /// sandboxes it stays a failure the user can retry.
    func testAPreconditionFailureWhereSandboxesCanRunStaysRetryable() async throws {
        let daemon = try await SandboxDaemon(events: .acceptThenRefuse)
        daemon.service.listRefusal.withLock {
            $0 = RPCError(code: .failedPrecondition, message: "sandbox write admission is closed")
        }
        let vm = SandboxesViewModel()

        await vm.loadSandboxes(client: daemon.client)
        XCTAssertNil(vm.unsupportedReason)
        guard case .failed = vm.loadState else {
            return XCTFail("expected a retryable failure, got \(vm.loadState)")
        }

        await daemon.close()
    }
}

/// A daemon that serves `SandboxService.Events`, `List` and `GetCapabilities`, for a running
/// QEMU System VM.
@MainActor
private final class SandboxDaemon {
    let manager = DaemonManager()
    let monitor = SandboxEventMonitor()
    let client: ArcBoxClient
    var status = Arcbox_V1_SetupStatus()
    var subscriptions: Int { service.subscriptions.withLock { $0 } }
    let service: SandboxService

    private let server: GRPCServer<HTTP2ServerTransport.TransportServices>
    private let serving: Task<Void, any Error>
    private let connections: Task<Void, any Error>
    private let socketPath: String

    init(events: SandboxService.EventsAnswer) async throws {
        socketPath =
            FileManager.default.temporaryDirectory
            .appendingPathComponent("sandbox-events-\(UUID().uuidString.prefix(8)).sock").path
        let transport = HTTP2ServerTransport.TransportServices(
            address: .unixDomainSocket(path: socketPath),
            transportSecurity: .plaintext
        )
        service = SandboxService(events: events)
        let server = GRPCServer(transport: transport, services: [service])
        self.server = server
        serving = Task { try await server.serve() }
        _ = try await transport.listeningAddress

        let client = try ArcBoxClient(socketPath: socketPath)
        self.client = client
        connections = Task { try await client.runConnections() }

        status.phase = .ready
        status.systemRuntime = .with { $0.state = .ready }
        status.effectiveBackend = .qemu
        manager.applySetupStatusSync(status)
    }

    func close() async {
        monitor.stop()
        client.close()
        connections.cancel()
        server.beginGracefulShutdown()
        _ = await serving.result
        try? FileManager.default.removeItem(atPath: socketPath)
    }
}

nonisolated private final class SandboxService: RegistrableRPCService {
    enum EventsAnswer: Sendable {
        /// Accept, then end the stream with an error that carries no detail.
        case acceptThenFail
        /// Accept, then end the stream refusing with `NESTED_VIRT_UNSUPPORTED`, as arcbox
        /// v0.11.1 and later do.
        case acceptThenRefuse
    }

    let events: EventsAnswer
    let subscriptions = Mutex(0)
    /// What `List` fails with; `nil` lists no sandboxes.
    let listRefusal = Mutex<RPCError?>(nil)
    /// What `GetCapabilities` reports.
    let nestedVirt = Mutex(Arcbox_Sandbox_V1_NestedVirtCapability.with { $0.supported = true })

    init(events: EventsAnswer) {
        self.events = events
    }

    /// The guest's refusal arcbox v0.11.2 relays from `List` without hardware virtualization,
    /// as captured from the daemon: no reason in the detail, and a message about the guest.
    static func guestRefusal() throws -> RPCError {
        let info = Arcbox_Sandbox_V1_ErrorInfo.with { $0.code = .nestedVirtUnsupported }
        return RPCError(
            GoogleRPCStatus(
                code: .failedPrecondition,
                message: """
                    core error: sandboxes require nested virtualization (/dev/kvm is missing in the guest): \
                    use the VZ backend on Apple Silicon M3 or newer with macOS 15+; the HV backend and \
                    Intel/M1/M2 hosts cannot run sandboxes
                    """,
                details: .any(try Google_Protobuf_Any(message: info))
            ))
    }

    /// The refusal arcbox#780 returns from every sandbox RPC before reaching the guest.
    static func hostRefusal(reason: String) throws -> RPCError {
        let info = Arcbox_Sandbox_V1_ErrorInfo.with {
            $0.code = .nestedVirtUnsupported
            $0.suggestion = "check `SandboxService.GetCapabilities` for this host's sandbox support"
            $0.context = ["reason": reason]
        }
        return RPCError(
            GoogleRPCStatus(
                code: .failedPrecondition,
                message: "sandboxes cannot run on this host: \(reason)",
                details: .any(try Google_Protobuf_Any(message: info))
            ))
    }

    func registerMethods<Transport: ServerTransport>(with router: inout RPCRouter<Transport>) {
        router.registerHandler(
            forMethod: Arcbox_Sandbox_V1_SandboxService.Method.Events.descriptor,
            deserializer: ProtobufDeserializer<Arcbox_Sandbox_V1_SandboxEventsRequest>(),
            serializer: ProtobufSerializer<Arcbox_Sandbox_V1_WatchEventsResponse>()
        ) { _, _ in
            self.subscriptions.withLock { $0 += 1 }
            switch self.events {
            case .acceptThenFail:
                return StreamingServerResponse { _ in
                    throw RPCError(code: .failedPrecondition, message: "the guest runs no sandboxes")
                }
            case .acceptThenRefuse:
                return StreamingServerResponse { _ in
                    let info = Arcbox_Sandbox_V1_ErrorInfo.with { $0.code = .nestedVirtUnsupported }
                    // A producer keeps only an RPCError's status and metadata; the server
                    // turns any other error into UNKNOWN.
                    throw RPCError(
                        GoogleRPCStatus(
                            code: .failedPrecondition,
                            message: "sandboxes cannot run on this host: no nested virtualization",
                            details: .any(try Google_Protobuf_Any(message: info))
                        ))
                }
            }
        }
        router.registerHandler(
            forMethod: Arcbox_Sandbox_V1_SandboxService.Method.List.descriptor,
            deserializer: ProtobufDeserializer<Arcbox_Sandbox_V1_ListSandboxesRequest>(),
            serializer: ProtobufSerializer<Arcbox_Sandbox_V1_ListSandboxesResponse>()
        ) { _, _ in
            if let refusal = self.listRefusal.withLock({ $0 }) { throw refusal }
            return StreamingServerResponse(single: ServerResponse(message: Arcbox_Sandbox_V1_ListSandboxesResponse()))
        }
        router.registerHandler(
            forMethod: Arcbox_Sandbox_V1_SandboxService.Method.GetCapabilities.descriptor,
            deserializer: ProtobufDeserializer<Arcbox_Sandbox_V1_GetCapabilitiesRequest>(),
            serializer: ProtobufSerializer<Arcbox_Sandbox_V1_GetCapabilitiesResponse>()
        ) { _, _ in
            let capabilities = Arcbox_Sandbox_V1_GetCapabilitiesResponse.with {
                $0.nestedVirt = self.nestedVirt.withLock { $0 }
            }
            return StreamingServerResponse(single: ServerResponse(message: capabilities))
        }
    }
}
