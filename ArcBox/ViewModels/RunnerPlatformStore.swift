import FleetPlatformClient
import Foundation
import Observation

@MainActor
protocol RunnerPlatformLoading: Sendable {
    func listWorkspaces() async throws -> [FleetWorkspace]
    func listMachines(workspaceID: String) async throws -> [FleetMachine]
    func getMachine(id: String, workspaceID: String) async throws -> FleetMachine
    func listJobs(
        workspaceID: String,
        machineID: String?,
        status: FleetRunnerJobStatus?,
        cursor: String?,
        limit: Int?
    ) async throws -> FleetRunnerJobPage
}

extension FleetPlatformClient: RunnerPlatformLoading {}

enum RunnerPlatformLoadState: Equatable {
    case idle
    case loading
    case loaded
    case machineNotFound
    case failed(String)
}

/// Window-scoped Platform history for the local machine reported by Fleet Agent.
@MainActor
@Observable
final class RunnerPlatformStore {
    private(set) var loadState: RunnerPlatformLoadState = .idle
    private(set) var workspace: FleetWorkspace?
    private(set) var machine: FleetMachine?
    private(set) var jobs: [FleetRunnerJob] = []
    private(set) var nextCursor: String?
    private(set) var isRefreshing = false
    private(set) var isLoadingMore = false
    private(set) var selection: RunnerSelection?

    @ObservationIgnored
    private var workspaceByMachineID: [String: FleetWorkspace] = [:]

    @ObservationIgnored
    private var refreshSequence = 0

    @ObservationIgnored
    private var historyBoundaryID: String?

    func observe(
        client: any RunnerPlatformLoading,
        machineID: String,
        interval: Duration = .seconds(30)
    ) async {
        while !Task.isCancelled {
            await refresh(client: client, machineID: machineID)
            guard !Task.isCancelled else { return }

            do {
                try await Task.sleep(for: interval)
            } catch {
                return
            }
        }
    }

    func refresh(client: any RunnerPlatformLoading, machineID: String) async {
        refreshSequence += 1
        let sequence = refreshSequence
        isRefreshing = true
        isLoadingMore = false
        if machine == nil || machine?.id != machineID {
            selection = nil
            workspace = nil
            machine = nil
            jobs = []
            historyBoundaryID = nil
            nextCursor = nil
            loadState = .loading
        }

        do {
            let snapshot = try await loadSnapshot(client: client, machineID: machineID, sequence: sequence)
            guard sequence == refreshSequence else { return }

            workspaceByMachineID[machineID] = snapshot.workspace
            workspace = snapshot.workspace
            machine = snapshot.machine
            jobs = snapshot.jobs.jobs
            // Rounded pages may include older rows. Keep the requested boundary stable across polls.
            historyBoundaryID = historyBoundaryID ?? jobs.last?.id
            nextCursor = snapshot.jobs.nextCursor
            loadState = .loaded
            isRefreshing = false
        } catch is CancellationError {
            guard sequence == refreshSequence else { return }
            isRefreshing = false
        } catch RunnerPlatformStoreError.machineNotFound {
            guard sequence == refreshSequence else { return }

            workspaceByMachineID[machineID] = nil
            workspace = nil
            machine = nil
            jobs = []
            historyBoundaryID = nil
            nextCursor = nil
            loadState = .machineNotFound
            isRefreshing = false
        } catch {
            guard sequence == refreshSequence else { return }

            loadState = .failed(FleetPlatformClient.userMessage(for: error))
            isRefreshing = false
        }
    }

    func loadMore(client: any RunnerPlatformLoading) async {
        guard let workspace, let machine, let cursor = nextCursor, !isRefreshing, !isLoadingMore else { return }
        let sequence = refreshSequence
        isLoadingMore = true
        defer {
            if sequence == refreshSequence { isLoadingMore = false }
        }

        do {
            let page = try await client.listJobs(
                workspaceID: workspace.id, machineID: machine.id, status: nil, cursor: cursor, limit: 50
            )
            guard sequence == refreshSequence else { return }
            jobs.append(contentsOf: page.jobs)
            historyBoundaryID = jobs.last?.id
            nextCursor = page.nextCursor
            loadState = .loaded
        } catch is CancellationError {
            return
        } catch {
            guard sequence == refreshSequence else { return }
            loadState = .failed(FleetPlatformClient.userMessage(for: error))
        }
    }

    func reset() {
        refreshSequence += 1
        workspaceByMachineID.removeAll()
        workspace = nil
        machine = nil
        jobs = []
        historyBoundaryID = nil
        nextCursor = nil
        loadState = .idle
        isRefreshing = false
        isLoadingMore = false
        selection = nil
    }

    var selectedJobID: String? {
        guard case .job(let jobID) = selection else { return nil }
        return jobID
    }

    func selectHost() {
        selection = .host
    }

    func selectJob(id: String) {
        selection = .job(id)
        if let historyBoundaryID, jobs.contains(where: { $0.id == id }) {
            self.historyBoundaryID = min(historyBoundaryID, id)
        }
    }

    func reconcileSelection(validJobIDs: Set<String>) {
        guard case .job(let jobID) = selection else { return }
        if !validJobIDs.contains(jobID) {
            selection = nil
        }
    }

    private func loadSnapshot(
        client: any RunnerPlatformLoading,
        machineID: String,
        sequence: Int
    ) async throws -> RunnerPlatformSnapshot {
        if let workspace = workspaceByMachineID[machineID] {
            let machine = try await client.getMachine(id: machineID, workspaceID: workspace.id)
            let jobs = try await loadJobs(
                client: client,
                workspaceID: workspace.id,
                machineID: machineID,
                sequence: sequence
            )
            return RunnerPlatformSnapshot(workspace: workspace, machine: machine, jobs: jobs)
        }

        for workspace in try await client.listWorkspaces() {
            let machines = try await client.listMachines(workspaceID: workspace.id)
            guard let machine = machines.first(where: { $0.id == machineID }) else {
                continue
            }
            let jobs = try await loadJobs(
                client: client,
                workspaceID: workspace.id,
                machineID: machineID,
                sequence: sequence
            )
            return RunnerPlatformSnapshot(workspace: workspace, machine: machine, jobs: jobs)
        }

        throw RunnerPlatformStoreError.machineNotFound
    }

    private func loadJobs(
        client: any RunnerPlatformLoading,
        workspaceID: String,
        machineID: String,
        sequence: Int
    ) async throws -> FleetRunnerJobPage {
        var page = try await client.listJobs(
            workspaceID: workspaceID, machineID: machineID, status: nil, cursor: nil, limit: 50
        )
        var jobs = page.jobs
        // Fleet orders prefixed UUIDv7 job IDs newest first. Read the boundary
        // after each response because selection can change during a request.
        while let cursor = page.nextCursor, let historyBoundaryID, let last = jobs.last, last.id > historyBoundaryID {
            guard sequence == refreshSequence else { throw CancellationError() }
            try Task.checkCancellation()
            page = try await client.listJobs(
                workspaceID: workspaceID, machineID: machineID, status: nil, cursor: cursor, limit: 50
            )
            jobs.append(contentsOf: page.jobs)
        }
        return FleetRunnerJobPage(jobs: jobs, nextCursor: page.nextCursor)
    }
}

private struct RunnerPlatformSnapshot {
    let workspace: FleetWorkspace
    let machine: FleetMachine
    let jobs: FleetRunnerJobPage
}

private enum RunnerPlatformStoreError: Error {
    case machineNotFound
}
