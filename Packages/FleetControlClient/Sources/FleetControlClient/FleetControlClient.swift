import Foundation
import GRPCCore
import GRPCNIOTransportHTTP2TransportServices
import os

/// High-level client for the local fleet-agent control API.
///
/// This client talks to the standalone fleet agent over its owner-only Unix
/// domain socket. It intentionally exposes desktop-friendly models instead of
/// generated protobuf stubs.
@available(macOS 15.0, *)
public final class FleetControlClient: Sendable {
    /// Default Unix socket path for the local fleet agent.
    public static let defaultSocketPath: String = {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        return "\(home)/.arcbox/fleet/agent.sock"
    }()

    /// Default timeout for unary RPCs.
    public static let defaultRPCTimeout: Duration = .seconds(15)

    private let socketPath: String
    private let _grpcClient: OSAllocatedUnfairLock<GRPCClient<HTTP2ClientTransport.TransportServices>>
    private let _closed: OSAllocatedUnfairLock<Bool>

    /// Creates a client targeting the given fleet-agent Unix socket.
    ///
    /// The transport is not started until ``runConnections()`` is called.
    public init(socketPath: String = FleetControlClient.defaultSocketPath) throws {
        self.socketPath = socketPath
        self._closed = OSAllocatedUnfairLock(initialState: false)

        let transport = try Self.makeTransport(socketPath: socketPath)
        self._grpcClient = OSAllocatedUnfairLock(
            initialState: GRPCClient(transport: transport)
        )
    }

    /// Run the gRPC transport with automatic recovery.
    ///
    /// Blocks until cancelled or ``close()`` is called. Service clients are
    /// recreated after transport termination, so callers should not cache
    /// generated service clients.
    public func runConnections() async throws {
        while !Task.isCancelled && !_closed.withLock({ $0 }) {
            let client = _grpcClient.withLock { $0 }

            do {
                try await client.runConnections()
            } catch is CancellationError {
                return
            } catch {
                FleetControlLog.grpc.warning("Fleet control transport failed, will recreate: \(error)")
            }

            guard !Task.isCancelled, !_closed.withLock({ $0 }) else { return }

            do {
                let transport = try Self.makeTransport(socketPath: socketPath)
                _grpcClient.withLock { $0 = GRPCClient(transport: transport) }
            } catch {
                FleetControlLog.grpc.warning("Failed to recreate fleet control transport: \(error)")
                try? await Task.sleep(for: .seconds(5))
                continue
            }

            try? await Task.sleep(for: .seconds(1))
        }
    }

    /// Whether the client has been closed.
    public var isClosed: Bool {
        _closed.withLock { $0 }
    }

    /// Initiates graceful shutdown of the transport.
    public func close() {
        let wasClosed = _closed.withLock { value -> Bool in
            let previous = value
            value = true
            return previous
        }

        guard !wasClosed else { return }
        _grpcClient.withLock { $0 }.beginGracefulShutdown()
        FleetControlLog.grpc.info("FleetControlClient closed")
    }

    /// Reads agent version and capability flags.
    public func getAgentInfo() async throws -> FleetAgentInfo {
        let response = try await lifecycle.getAgentInfo(
            .init(),
            options: Self.defaultCallOptions
        )
        return FleetAgentInfo(proto: response)
    }

    /// Enrolls this host with an enrollment token.
    ///
    /// The machine credential is exchanged and persisted by the fleet agent,
    /// not by the desktop app.
    public func enroll(token: String, controlPlane: String? = nil) async throws -> String {
        var request = Arcbox_Fleet_Control_V1_EnrollRequest()
        request.enrollmentToken = token
        if let controlPlane {
            request.controlPlane = controlPlane
        }

        let response = try await lifecycle.enroll(
            request,
            options: Self.defaultCallOptions
        )
        return response.machineID
    }

    /// Stops accepting new offers while allowing in-flight jobs to finish.
    public func drain() async throws {
        _ = try await lifecycle.drain(
            .init(),
            options: Self.defaultCallOptions
        )
    }

    /// Resumes accepting offers after draining.
    public func resume() async throws {
        _ = try await lifecycle.resume(
            .init(),
            options: Self.defaultCallOptions
        )
    }

    /// Removes the persisted machine credential and returns to unenrolled.
    public func unenroll() async throws {
        _ = try await lifecycle.unenroll(
            .init(),
            options: Self.defaultCallOptions
        )
    }

    /// Reads coarse lifecycle status.
    public func getStatus() async throws -> FleetAgentStatus {
        let response = try await lifecycle.getStatus(
            .init(),
            options: Self.defaultCallOptions
        )
        return FleetAgentStatus(proto: response)
    }

    /// Streams live agent snapshots.
    ///
    /// The first yielded value is the current snapshot, followed by updates as
    /// the agent state changes. The stream finishes with an error if the RPC
    /// fails; ViewModels should reconnect with backoff.
    public func watchSnapshots() -> AsyncThrowingStream<FleetAgentSnapshot, Error> {
        AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let service = state
                    try await service.watch(
                        .init(),
                        options: Self.streamingCallOptions
                    ) { response in
                        for try await message in response.messages {
                            guard let snapshot = FleetAgentSnapshot(proto: message) else {
                                continue
                            }
                            continuation.yield(snapshot)
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// Prepares the requested image settings and streams their progress.
    ///
    /// An empty kinds array asks the agent to prepare every supported image.
    public func prepareImages(
        _ kinds: [FleetImageKind] = []
    ) -> AsyncThrowingStream<FleetImagePreparationEvent, Error> {
        let request: Arcbox_Fleet_Control_V1_PrepareRequest = {
            var request = Arcbox_Fleet_Control_V1_PrepareRequest()
            request.kinds = kinds.map(\.protoValue)
            return request
        }()

        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    let service = image
                    try await service.prepare(
                        request,
                        options: Self.streamingCallOptions
                    ) { response in
                        for try await message in response.messages {
                            continuation.yield(FleetImagePreparationEvent(proto: message))
                        }
                    }
                    continuation.finish()
                } catch is CancellationError {
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { @Sendable _ in
                task.cancel()
            }
        }
    }

    /// Reads the current persisted agent settings.
    public func getSettings() async throws -> FleetAgentSettings {
        let response = try await settings.getSettings(
            .init(),
            options: Self.defaultCallOptions
        )
        guard response.hasSettings else {
            return FleetAgentSettings()
        }
        return FleetAgentSettings(proto: response.settings)
    }

    /// Applies a partial settings update.
    ///
    /// Nil update fields are omitted from the request, preserving proto
    /// presence semantics.
    public func updateSettings(_ update: FleetSettingsUpdate) async throws -> FleetAgentSettings {
        let response = try await settings.updateSettings(
            update.protoValue,
            options: Self.defaultCallOptions
        )
        guard response.hasSettings else {
            return FleetAgentSettings()
        }
        return FleetAgentSettings(proto: response.settings)
    }

    /// Applies a partial settings update.
    public func updateSettings(
        loadCeiling: Double? = nil,
        memFloorMib: UInt64? = nil,
        linuxRunnerImage: String? = nil,
        gateway: String? = nil,
        dockerMode: FleetDockerMode? = nil,
        runnerScript: String? = nil,
        participate: Bool? = nil
    ) async throws -> FleetAgentSettings {
        try await updateSettings(
            FleetSettingsUpdate(
                loadCeiling: loadCeiling,
                memFloorMib: memFloorMib,
                linuxRunnerImage: linuxRunnerImage,
                gateway: gateway,
                dockerMode: dockerMode,
                runnerScript: runnerScript,
                participate: participate
            )
        )
    }

    /// Maps transport and gRPC failures to UI-friendly text.
    public static func userMessage(for error: Error) -> String {
        let description = String(describing: error)

        if description.contains("unavailable") || description.contains("UNAVAILABLE") {
            return "Cannot reach the fleet agent. Is it running?"
        }
        if description.contains("No such file")
            || description.contains("ENOENT")
            || description.contains("agent.sock")
        {
            return "Fleet agent is not running."
        }
        if description.contains("deadline") || description.contains("DEADLINE_EXCEEDED") {
            return "Operation timed out. The fleet agent may be busy."
        }
        if description.contains("permission") || description.contains("PERMISSION_DENIED") {
            return "Permission denied. Check fleet agent socket permissions."
        }
        if description.contains("already exists") || description.contains("ALREADY_EXISTS") {
            return "This Mac is already enrolled in the fleet."
        }
        if description.contains("not found") || description.contains("NOT_FOUND") {
            return "Fleet resource not found."
        }
        if description.contains("invalid argument") || description.contains("INVALID_ARGUMENT") {
            return "Fleet settings were rejected by the agent."
        }
        if description.contains("ECONNREFUSED") || description.contains("Connection refused") {
            return "Connection refused. Is the fleet agent running?"
        }

        return error.localizedDescription
    }

    private static var defaultCallOptions: GRPCCore.CallOptions {
        var options = CallOptions.defaults
        options.timeout = defaultRPCTimeout
        return options
    }

    private static var streamingCallOptions: GRPCCore.CallOptions {
        .defaults
    }

    private static func makeTransport(
        socketPath: String
    ) throws -> HTTP2ClientTransport.TransportServices {
        try HTTP2ClientTransport.TransportServices(
            target: .unixDomainSocket(path: socketPath),
            transportSecurity: .plaintext,
            config: .defaults { $0.http2.authority = "arcbox-fleet.local" }
        )
    }

    private var grpcClient: GRPCClient<HTTP2ClientTransport.TransportServices> {
        _grpcClient.withLock { $0 }
    }

    private var lifecycle:
        Arcbox_Fleet_Control_V1_FleetLifecycleService.Client<
            HTTP2ClientTransport.TransportServices
        >
    {
        .init(wrapping: grpcClient)
    }

    private var state:
        Arcbox_Fleet_Control_V1_FleetStateService.Client<
            HTTP2ClientTransport.TransportServices
        >
    {
        .init(wrapping: grpcClient)
    }

    private var settings:
        Arcbox_Fleet_Control_V1_FleetSettingsService.Client<
            HTTP2ClientTransport.TransportServices
        >
    {
        .init(wrapping: grpcClient)
    }

    private var image:
        Arcbox_Fleet_Control_V1_FleetImageService.Client<
            HTTP2ClientTransport.TransportServices
        >
    {
        .init(wrapping: grpcClient)
    }
}
