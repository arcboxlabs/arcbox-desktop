import ArcBoxClient
import Foundation
import GRPCCore
import Observation

struct OnboardingMigrationPreview: Equatable {
    let source: DockerMigrationSource
    let daemonName: String
    let serverVersion: String
    let imageCount: UInt32
    let volumeCount: UInt32
    let networkCount: UInt32
    let containerCount: UInt32
    let warnings: [String]
    let unsupportedResources: [String]
    let replacementsRequired: Bool
    let replacements: Arcbox_V1_MigrationReplacementSummary
    let stopsSourceContainers: Bool

    init(
        source: DockerMigrationSource,
        response: Arcbox_V1_PrepareMigrationResponse
    ) {
        self.source = source
        daemonName = response.plan.source.daemonName
        serverVersion = response.plan.source.serverVersion
        imageCount = response.imageCount
        volumeCount = response.volumeCount
        networkCount = response.networkCount
        containerCount = response.containerCount
        warnings = response.warnings
        unsupportedResources = response.unsupportedResources
        replacementsRequired = response.replacementsRequired
        replacements = response.plan.replacements
        stopsSourceContainers = !response.plan.blockers.isEmpty
    }

    var totalResourceCount: UInt64 {
        UInt64(imageCount)
            + UInt64(volumeCount)
            + UInt64(networkCount)
            + UInt64(containerCount)
    }

    var canRun: Bool {
        unsupportedResources.isEmpty
    }

    var confirmationMessages: [String] {
        var messages: [String] = []
        if !replacements.containers.isEmpty {
            messages.append("ArcBox containers will be replaced: \(replacements.containers.joined(separator: ", ")).")
        }
        if !replacements.volumes.isEmpty {
            messages.append(
                "Existing ArcBox volume data will be replaced: \(replacements.volumes.joined(separator: ", ")).")
        }
        if !replacements.networks.isEmpty {
            messages.append("ArcBox networks will be replaced: \(replacements.networks.joined(separator: ", ")).")
        }
        if !replacements.imageTags.isEmpty {
            messages.append("ArcBox image tags will be replaced: \(replacements.imageTags.joined(separator: ", ")).")
        }
        if stopsSourceContainers {
            messages.append("Source containers using migrated volumes will be stopped.")
        }
        return messages
    }

    // Formal prepare omits the full plan. Warnings include required source stops and container names.
    func matches(_ response: Arcbox_V1_PrepareMigrationResponse) -> Bool {
        response.sourceKind == source.kind.rawValue
            && URL(fileURLWithPath: response.sourceSocketPath).standardizedFileURL.path
                == URL(fileURLWithPath: source.socketPath).standardizedFileURL.path
            && response.imageCount == imageCount
            && response.volumeCount == volumeCount
            && response.networkCount == networkCount
            && response.containerCount == containerCount
            && response.replacementsRequired == replacementsRequired
            && Set(response.warnings) == Set(warnings)
    }
}

struct OnboardingMigrationProgress: Equatable {
    let phase: String
    let resource: String
    let message: String
    let completed: UInt32
    let total: UInt32

    var fractionCompleted: Double? {
        guard total > 0 else { return nil }
        return min(Double(completed) / Double(total), 1)
    }
}

@Observable
@MainActor
final class OnboardingMigrationModel {
    enum State: Equatable {
        case idle
        case checking
        case unavailable
        case empty(DockerMigrationSource)
        case review(OnboardingMigrationPreview)
        case preparing(OnboardingMigrationPreview)
        case migrating(OnboardingMigrationPreview, OnboardingMigrationProgress)
        case completed(OnboardingMigrationPreview, warnings: [String])
        case failed(OnboardingMigrationPreview?, message: String)

        var isExecuting: Bool {
            switch self {
            case .preparing, .migrating:
                true
            default:
                false
            }
        }
    }

    private(set) var state: State = .idle

    @ObservationIgnored
    private let detectSource: @MainActor () async throws -> DockerMigrationSource?

    @ObservationIgnored
    private let prepareMigration:
        @MainActor (Arcbox_V1_PrepareMigrationRequest) async throws -> Arcbox_V1_PrepareMigrationResponse

    @ObservationIgnored
    private let runMigrationStream:
        @MainActor (
            Arcbox_V1_RunMigrationRequest,
            @escaping @MainActor @Sendable (Arcbox_V1_RunMigrationEvent) -> Void
        ) async throws -> Bool

    @ObservationIgnored
    private var previewTask: Task<Void, Never>?

    @ObservationIgnored
    private var migrationTask: Task<Void, Never>?

    @ObservationIgnored
    private var isTerminating = false

    private static var prepareCallOptions: CallOptions {
        var options = CallOptions.defaults
        options.timeout = .seconds(120)
        return options
    }

    convenience init(clientProvider: @escaping @MainActor () -> ArcBoxClient?) {
        self.init(
            detectSource: { try await DockerContextManager.detectMigrationSource() },
            prepareMigration: { request in
                guard let client = clientProvider() else {
                    throw RPCError(code: .failedPrecondition, message: "ArcBox runtime is not ready.")
                }
                return try await client.migration.prepareMigration(
                    request,
                    options: Self.prepareCallOptions
                )
            },
            runMigrationStream: { request, receive in
                guard let client = clientProvider() else {
                    throw RPCError(code: .failedPrecondition, message: "ArcBox runtime is not ready.")
                }
                return try await client.migration.runMigration(request) { response in
                    for try await event in response.messages {
                        try Task.checkCancellation()
                        await receive(event)
                        if event.done { return true }
                    }
                    return false
                }
            }
        )
    }

    init(
        detectSource: @escaping @MainActor () async throws -> DockerMigrationSource?,
        prepareMigration:
            @escaping @MainActor (Arcbox_V1_PrepareMigrationRequest) async throws ->
            Arcbox_V1_PrepareMigrationResponse,
        runMigrationStream:
            @escaping @MainActor (
                Arcbox_V1_RunMigrationRequest,
                @escaping @MainActor @Sendable (Arcbox_V1_RunMigrationEvent) -> Void
            ) async throws -> Bool
    ) {
        self.detectSource = detectSource
        self.prepareMigration = prepareMigration
        self.runMigrationStream = runMigrationStream
    }

    func loadPreview() async {
        guard !isTerminating, migrationTask == nil else { return }
        if let previewTask {
            await previewTask.value
            return
        }
        state = .checking
        let task = Task {
            await fetchPreview()
            previewTask = nil
        }
        previewTask = task
        await task.value
    }

    private func fetchPreview() async {
        do {
            guard let source = try await detectSource() else {
                state = .unavailable
                return
            }
            try Task.checkCancellation()

            var request = Arcbox_V1_PrepareMigrationRequest()
            request.sourceKind = source.kind.rawValue
            request.sourceSocketPath = source.socketPath
            request.allowReplacements = true
            request.dryRun = true

            let response = try await prepareMigration(request)
            try Task.checkCancellation()
            guard response.hasPlan else {
                state = .failed(
                    nil,
                    message: "ArcBox returned an incomplete migration preview."
                )
                return
            }

            let preview = OnboardingMigrationPreview(source: source, response: response)
            if preview.totalResourceCount == 0 && preview.unsupportedResources.isEmpty {
                state = .empty(source)
            } else {
                state = .review(preview)
            }
        } catch is CancellationError {
            state = .idle
        } catch {
            state = .failed(nil, message: ArcBoxClient.userMessage(for: error))
        }
    }

    func startMigration() {
        guard
            !isTerminating,
            migrationTask == nil,
            case .review(let preview) = state,
            preview.canRun
        else { return }
        state = .preparing(preview)
        migrationTask = Task {
            await runMigration(preview)
            migrationTask = nil
        }
    }

    func retry() {
        Task { await loadPreview() }
    }

    func beginTermination() {
        isTerminating = true
        previewTask?.cancel()
    }

    func waitForCompletion() async {
        await previewTask?.value
        await migrationTask?.value
    }

    private func runMigration(_ preview: OnboardingMigrationPreview) async {
        let prepared: Arcbox_V1_PrepareMigrationResponse
        do {
            var prepareRequest = Arcbox_V1_PrepareMigrationRequest()
            prepareRequest.sourceKind = preview.source.kind.rawValue
            prepareRequest.sourceSocketPath = preview.source.socketPath
            prepareRequest.allowReplacements = true

            prepared = try await prepareMigration(prepareRequest)
            guard prepared.unsupportedResources.isEmpty else {
                state = .failed(
                    nil,
                    message: prepared.unsupportedResources.joined(separator: "\n")
                )
                return
            }
            guard preview.matches(prepared) else {
                state = .failed(
                    nil,
                    message:
                        "The source environment changed after the preview. "
                        + "Review the updated migration plan before continuing."
                )
                return
            }
            guard !prepared.planID.isEmpty else {
                state = .failed(
                    preview,
                    message: "ArcBox did not return an executable migration plan."
                )
                return
            }
        } catch {
            state = .failed(preview, message: ArcBoxClient.userMessage(for: error))
            return
        }

        var runRequest = Arcbox_V1_RunMigrationRequest()
        runRequest.planID = prepared.planID
        runRequest.allowReplacements = true

        state = .migrating(
            preview,
            OnboardingMigrationProgress(
                phase: "prepare",
                resource: "",
                message: "Starting migration…",
                completed: 0,
                total: 0
            )
        )

        await observeMigration(request: runRequest, preview: preview)
    }

    private func observeMigration(
        request: Arcbox_V1_RunMigrationRequest,
        preview: OnboardingMigrationPreview
    ) async {
        var retryDelaySeconds: UInt64 = 1
        while !Task.isCancelled {
            do {
                let reachedTerminalEvent = try await runMigrationStream(request) { event in
                    self.receive(event, preview: preview)
                }
                if reachedTerminalEvent { return }
                retryDelaySeconds = 1
            } catch let error as RPCError {
                if error.code == .notFound {
                    state = .failed(
                        preview,
                        message:
                            "The ArcBox daemon restarted before migration completed. "
                            + "Review the source environment before trying again."
                    )
                    return
                }
                guard Self.shouldReconnect(after: error.code) else {
                    state = .failed(preview, message: ArcBoxClient.userMessage(for: error))
                    return
                }
            } catch {
                state = .failed(preview, message: ArcBoxClient.userMessage(for: error))
                return
            }

            state = .migrating(
                preview,
                OnboardingMigrationProgress(
                    phase: "reconnecting",
                    resource: "",
                    message: "Reconnecting to the migration…",
                    completed: 0,
                    total: 0
                )
            )
            do {
                try await Task.sleep(for: .seconds(retryDelaySeconds))
            } catch {
                return
            }
            retryDelaySeconds = min(retryDelaySeconds * 2, 8)
        }
    }

    nonisolated static func shouldReconnect(after code: RPCError.Code) -> Bool {
        code == .unavailable
    }

    private func receive(
        _ event: Arcbox_V1_RunMigrationEvent,
        preview: OnboardingMigrationPreview
    ) {
        if event.done {
            if event.success {
                state = .completed(preview, warnings: event.warnings)
            } else {
                state = .failed(
                    preview,
                    message: event.message.isEmpty ? "Migration failed." : event.message
                )
            }
            return
        }

        state = .migrating(
            preview,
            OnboardingMigrationProgress(
                phase: event.phase,
                resource: event.resource,
                message: event.message,
                completed: event.completed,
                total: event.total
            )
        )
    }
}
