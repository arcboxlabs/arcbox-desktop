import ArcBoxClient
import Foundation
import GRPCCore
import Observation

@Observable
@MainActor
final class RuntimeStorageRecoveryModel {
    private(set) var progress: Arcbox_V1_StorageRecoveryProgress?
    private(set) var mayBeRunning = false
    private(set) var errorMessage: String?

    @ObservationIgnored private var task: Task<Void, Never>?
    @ObservationIgnored private var isTerminating = false
    @ObservationIgnored private var previousOperationID: String?
    @ObservationIgnored private let run:
        @MainActor (
            Arcbox_V1_RecoverStorageRequest.Action,
            @escaping @MainActor @Sendable (Arcbox_V1_StorageRecoveryProgress) -> Void
        ) async throws -> Void

    convenience init(
        clientProvider: @escaping @MainActor () -> ArcBoxClient?,
        migrationIsRunning: @escaping @MainActor () -> Bool = { false }
    ) {
        self.init { action, receive in
            guard !migrationIsRunning() else {
                throw RPCError(
                    code: .failedPrecondition, message: "Wait for migration to finish before recovering storage.")
            }
            guard let client = clientProvider() else {
                throw RPCError(code: .failedPrecondition, message: "ArcBox runtime is not connected.")
            }
            var request = Arcbox_V1_RecoverStorageRequest()
            request.action = action
            try await client.system.recoverStorage(request) { response in
                for try await progress in response.messages {
                    await receive(progress)
                    if progress.phase.isTerminal { return }
                }
            }
        }
    }

    init(
        run:
            @escaping @MainActor (
                Arcbox_V1_RecoverStorageRequest.Action,
                @escaping @MainActor @Sendable (Arcbox_V1_StorageRecoveryProgress) -> Void
            ) async throws -> Void
    ) {
        self.run = run
    }

    func start(_ action: Arcbox_V1_RecoverStorageRequest.Action) {
        guard !isTerminating, !mayBeRunning, task == nil else { return }
        previousOperationID = progress?.operationID
        progress = nil
        errorMessage = nil
        mayBeRunning = true
        task = Task {
            defer { task = nil }
            do {
                try await run(action) { self.receive($0) }
                if mayBeRunning {
                    errorMessage = Self.interruptedMessage
                }
            } catch {
                if progress?.phase.isTerminal == true { return }
                if progress == nil, let rpc = error as? RPCError,
                    [.failedPrecondition, .invalidArgument, .unimplemented].contains(rpc.code)
                {
                    mayBeRunning = false
                    errorMessage = ArcBoxClient.userMessage(for: error)
                } else {
                    errorMessage = "\(Self.interruptedMessage) \(ArcBoxClient.userMessage(for: error))"
                }
            }
        }
    }

    /// Recovery replay must continue while termination waits for the direct stream.
    func observe(_ daemon: DaemonManager) {
        let observation = withObservationTracking {
            daemon.storageRecovery
        } onChange: { [weak self, weak daemon] in
            Task { @MainActor in
                guard let self, let daemon else { return }
                self.observe(daemon)
            }
        }
        reconcile(observation)
    }

    /// SetupStatus replays server-owned progress after a stream drop or app restart.
    func reconcile(_ observation: Arcbox_V1_StorageRecoveryProgress?) {
        guard let observation else { return }
        if observation.operationID == previousOperationID { return }
        if mayBeRunning, let progress, observation.operationID != progress.operationID { return }
        receive(observation)
        if progress?.phase.isTerminal == true { task?.cancel() }
    }

    private func receive(_ observation: Arcbox_V1_StorageRecoveryProgress) {
        guard !observation.operationID.isEmpty else { return }
        if let progress, progress.operationID == observation.operationID, progress.phase.isTerminal { return }
        var next = observation
        if next.recoveryDirectory.isEmpty, next.operationID == progress?.operationID {
            next.recoveryDirectory = progress?.recoveryDirectory ?? ""
        }
        progress = next
        mayBeRunning = !next.phase.isTerminal
        errorMessage = nil
    }

    func beginTermination() {
        isTerminating = true
    }

    func waitForCompletion() async {
        await task?.value
    }

    private static let interruptedMessage =
        "Recovery completion is unknown. ArcBox will keep the runtime running and wait for its recovery status. Do not start another recovery."
}

extension Arcbox_V1_StorageRecoveryProgress {
    var statusLabel: String {
        guard phase == .complete else { return phase.label }
        return storageProtected ? "Storage checked; runtime remains stopped" : "Read-write recovery completed"
    }
}

extension Arcbox_V1_StorageRecoveryProgress.Phase {
    nonisolated var isTerminal: Bool { self == .complete || self == .failed }

    var label: String {
        switch self {
        case .stopping: "Stopping workloads"
        case .preserving: "Preserving runtime disks"
        case .checking: "Checking filesystems"
        case .restarting: "Restarting runtime"
        case .verifying: "Verifying writes"
        case .complete: "Completed"
        case .failed: "Recovery needs attention"
        case .unspecified, .UNRECOGNIZED: "Waiting for recovery status"
        }
    }
}
