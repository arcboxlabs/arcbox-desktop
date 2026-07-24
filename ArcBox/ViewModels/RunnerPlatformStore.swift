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
    private(set) var selection: RunnerSelection?

    @ObservationIgnored
    private var workspaceByMachineID: [String: FleetWorkspace] = [:]

    @ObservationIgnored
    private var refreshSequence = 0

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
        if machine == nil || machine?.id != machineID {
            selection = nil
            loadState = .loading
        }

        do {
            let snapshot = try await loadSnapshot(client: client, machineID: machineID)
            guard sequence == refreshSequence else { return }

            workspaceByMachineID[machineID] = snapshot.workspace
            workspace = snapshot.workspace
            machine = snapshot.machine
            jobs = snapshot.jobs.jobs
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
            nextCursor = nil
            loadState = .machineNotFound
            isRefreshing = false
        } catch {
            guard sequence == refreshSequence else { return }

            loadState = .failed(FleetPlatformClient.userMessage(for: error))
            isRefreshing = false
        }
    }

    func reset() {
        refreshSequence += 1
        workspaceByMachineID.removeAll()
        workspace = nil
        machine = nil
        jobs = []
        nextCursor = nil
        loadState = .idle
        isRefreshing = false
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
    }

    func reconcileSelection(validJobIDs: Set<String>) {
        guard case .job(let jobID) = selection else { return }
        if !validJobIDs.contains(jobID) {
            selection = nil
        }
    }

    private func loadSnapshot(
        client: any RunnerPlatformLoading,
        machineID: String
    ) async throws -> RunnerPlatformSnapshot {
        if let workspace = workspaceByMachineID[machineID] {
            let machine = try await client.getMachine(id: machineID, workspaceID: workspace.id)
            let jobs = try await client.listJobs(
                workspaceID: workspace.id,
                machineID: machineID,
                status: nil,
                cursor: nil,
                limit: 50
            )
            return RunnerPlatformSnapshot(workspace: workspace, machine: machine, jobs: jobs)
        }

        for workspace in try await client.listWorkspaces() {
            let machines = try await client.listMachines(workspaceID: workspace.id)
            guard let machine = machines.first(where: { $0.id == machineID }) else {
                continue
            }
            let jobs = try await client.listJobs(
                workspaceID: workspace.id,
                machineID: machineID,
                status: nil,
                cursor: nil,
                limit: 50
            )
            return RunnerPlatformSnapshot(workspace: workspace, machine: machine, jobs: jobs)
        }

        throw RunnerPlatformStoreError.machineNotFound
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
