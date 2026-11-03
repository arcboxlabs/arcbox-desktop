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
        let daemon = try await SandboxEventsDaemon(answer: .acceptThenFail)
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
        let daemon = try await SandboxEventsDaemon(answer: .acceptThenRefuse)
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
}

/// A daemon that serves only `SandboxService.Events`, for a running QEMU System VM.
@MainActor
private final class SandboxEventsDaemon {
    let manager = DaemonManager()
    let monitor = SandboxEventMonitor()
    let client: ArcBoxClient
    var status = Arcbox_V1_SetupStatus()
    var subscriptions: Int { service.subscriptions.withLock { $0 } }

    private let service: EventsService
    private let server: GRPCServer<HTTP2ServerTransport.TransportServices>
    private let serving: Task<Void, any Error>
    private let connections: Task<Void, any Error>
    private let socketPath: String

    init(answer: EventsService.Answer) async throws {
        socketPath =
            FileManager.default.temporaryDirectory
            .appendingPathComponent("sandbox-events-\(UUID().uuidString.prefix(8)).sock").path
        let transport = HTTP2ServerTransport.TransportServices(
            address: .unixDomainSocket(path: socketPath),
            transportSecurity: .plaintext
        )
        service = EventsService(answer: answer)
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

nonisolated private final class EventsService: RegistrableRPCService {
    enum Answer: Sendable {
        /// Accept, then end the stream with an error that carries no detail.
        case acceptThenFail
        /// Accept, then end the stream refusing with `NESTED_VIRT_UNSUPPORTED`, as arcbox
        /// v0.11.1 and later do.
        case acceptThenRefuse
    }

    let answer: Answer
    let subscriptions = Mutex(0)

    init(answer: Answer) {
        self.answer = answer
    }

    func registerMethods<Transport: ServerTransport>(with router: inout RPCRouter<Transport>) {
        router.registerHandler(
            forMethod: Arcbox_Sandbox_V1_SandboxService.Method.Events.descriptor,
            deserializer: ProtobufDeserializer<Arcbox_Sandbox_V1_SandboxEventsRequest>(),
            serializer: ProtobufSerializer<Arcbox_Sandbox_V1_WatchEventsResponse>()
        ) { _, _ in
            self.subscriptions.withLock { $0 += 1 }
            switch self.answer {
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
    }
}
