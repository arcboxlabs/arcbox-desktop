import FleetPlatformClient
import XCTest

@testable import ArcBox

@MainActor
final class RunnerPlatformStoreTests: XCTestCase {
    func testResolvesAgentMachineAcrossWorkspacesAndLoadsItsJobs() async throws {
        let personal = workspace(id: "ws_personal", name: "Personal")
        let team = workspace(id: "ws_team", name: "Team")
        let machine = machine(id: "fltm_local", name: "This Mac")
        let job = job(id: "job_current", machineID: machine.id)
        let client = StubRunnerPlatformClient(
            workspaces: [personal, team],
            machinesByWorkspace: [
                personal.id: [self.machine(id: "fltm_other", name: "Other Mac")],
                team.id: [machine],
            ],
            jobPage: FleetRunnerJobPage(jobs: [job], nextCursor: "older")
        )
        let store = RunnerPlatformStore()

        await store.refresh(client: client, machineID: machine.id)

        XCTAssertEqual(store.loadState, .loaded)
        XCTAssertEqual(store.workspace, team)
        XCTAssertEqual(store.machine, machine)
        XCTAssertEqual(store.jobs, [job])
        XCTAssertEqual(store.nextCursor, "older")
        XCTAssertEqual(client.listedMachineWorkspaces, [personal.id, team.id])
        XCTAssertEqual(client.jobMachineIDs, [machine.id])
    }

    func testRefreshReusesResolvedWorkspaceWithoutScanningAgain() async {
        let workspace = workspace(id: "ws_team", name: "Team")
        let machine = machine(id: "fltm_local", name: "This Mac")
        let client = StubRunnerPlatformClient(
            workspaces: [workspace],
            machinesByWorkspace: [workspace.id: [machine]],
            jobPage: FleetRunnerJobPage(jobs: [], nextCursor: nil)
        )
        let store = RunnerPlatformStore()

        await store.refresh(client: client, machineID: machine.id)
        await store.refresh(client: client, machineID: machine.id)

        XCTAssertEqual(client.listWorkspacesCallCount, 1)
        XCTAssertEqual(client.listedMachineWorkspaces, [workspace.id])
        XCTAssertEqual(client.requestedMachineIDs, [machine.id])
        XCTAssertEqual(client.jobMachineIDs, [machine.id, machine.id])
    }

    func testMissingMachineHasExplicitState() async {
        let workspace = workspace(id: "ws_team", name: "Team")
        let client = StubRunnerPlatformClient(
            workspaces: [workspace],
            machinesByWorkspace: [workspace.id: []],
            jobPage: FleetRunnerJobPage(jobs: [], nextCursor: nil)
        )
        let store = RunnerPlatformStore()

        await store.refresh(client: client, machineID: "fltm_missing")

        XCTAssertEqual(store.loadState, .machineNotFound)
        XCTAssertNil(store.workspace)
        XCTAssertNil(store.machine)
        XCTAssertTrue(store.jobs.isEmpty)
    }

    func testLateRefreshCannotOverwriteNewMachine() async {
        let oldWorkspace = workspace(id: "ws_old", name: "Old")
        let oldMachine = machine(id: "fltm_old", name: "Old Mac")
        let slowClient = SuspendedRunnerPlatformClient(
            workspace: oldWorkspace,
            machine: oldMachine
        )
        let newWorkspace = workspace(id: "ws_new", name: "New")
        let newMachine = machine(id: "fltm_new", name: "New Mac")
        let fastClient = StubRunnerPlatformClient(
            workspaces: [newWorkspace],
            machinesByWorkspace: [newWorkspace.id: [newMachine]],
            jobPage: FleetRunnerJobPage(
                jobs: [job(id: "job_new", machineID: newMachine.id)],
                nextCursor: nil
            )
        )
        let store = RunnerPlatformStore()

        let oldRefresh = Task {
            await store.refresh(client: slowClient, machineID: oldMachine.id)
        }
        await slowClient.waitUntilStarted()

        await store.refresh(client: fastClient, machineID: newMachine.id)
        slowClient.resume()
        await oldRefresh.value

        XCTAssertEqual(store.workspace, newWorkspace)
        XCTAssertEqual(store.machine, newMachine)
        XCTAssertEqual(store.jobs.map(\.id), ["job_new"])
    }

    func testSelectionSwitchesBetweenHostAndJob() {
        let store = RunnerPlatformStore()

        store.selectHost()
        XCTAssertEqual(store.selection, .host)
        XCTAssertNil(store.selectedJobID)

        store.selectJob(id: "job_123")
        XCTAssertEqual(store.selection, .job("job_123"))
        XCTAssertEqual(store.selectedJobID, "job_123")
    }

    func testReconcileClearsOnlyMissingJobSelection() {
        let store = RunnerPlatformStore()

        store.selectJob(id: "job_123")
        store.reconcileSelection(validJobIDs: ["job_123"])
        XCTAssertEqual(store.selection, .job("job_123"))

        store.reconcileSelection(validJobIDs: ["job_other"])
        XCTAssertNil(store.selection)

        store.selectHost()
        store.reconcileSelection(validJobIDs: [])
        XCTAssertEqual(store.selection, .host)
    }

    func testResetClearsSelection() {
        let store = RunnerPlatformStore()
        store.selectHost()

        store.reset()

        XCTAssertNil(store.selection)
    }

    private func workspace(id: String, name: String) -> FleetWorkspace {
        FleetWorkspace(
            id: id,
            name: name,
            plan: "free",
            createdAt: .distantPast,
            updatedAt: .distantPast
        )
    }

    private func machine(id: String, name: String) -> FleetMachine {
        FleetMachine(
            id: id,
            name: name,
            status: .online,
            arch: "arm64",
            cpu: 12,
            memMib: 24_576,
            tags: [],
            createdAt: .distantPast,
            enrolledAt: .distantPast,
            lastSeen: .distantPast,
            agentVersion: "0.5.1",
            pools: [],
            telemetry: nil
        )
    }

    private func job(id: String, machineID: String) -> FleetRunnerJob {
        FleetRunnerJob(
            id: id,
            repo: "arcboxlabs/arcbox",
            status: .running,
            os: .darwin,
            arch: .arm64,
            githubRunID: 123,
            githubJobID: 456,
            labels: [],
            machineID: machineID,
            jitRunnerName: nil,
            createdAt: .distantPast,
            startedAt: .distantPast,
            finishedAt: nil
        )
    }
}

@MainActor
private final class StubRunnerPlatformClient: RunnerPlatformLoading {
    let workspaces: [FleetWorkspace]
    let machinesByWorkspace: [String: [FleetMachine]]
    let jobPage: FleetRunnerJobPage

    private(set) var listWorkspacesCallCount = 0
    private(set) var listedMachineWorkspaces: [String] = []
    private(set) var requestedMachineIDs: [String] = []
    private(set) var jobMachineIDs: [String] = []

    init(
        workspaces: [FleetWorkspace],
        machinesByWorkspace: [String: [FleetMachine]],
        jobPage: FleetRunnerJobPage
    ) {
        self.workspaces = workspaces
        self.machinesByWorkspace = machinesByWorkspace
        self.jobPage = jobPage
    }

    func listWorkspaces() async throws -> [FleetWorkspace] {
        listWorkspacesCallCount += 1
        return workspaces
    }

    func listMachines(workspaceID: String) async throws -> [FleetMachine] {
        listedMachineWorkspaces.append(workspaceID)
        return machinesByWorkspace[workspaceID] ?? []
    }

    func getMachine(id: String, workspaceID: String) async throws -> FleetMachine {
        requestedMachineIDs.append(id)
        return try XCTUnwrap(machinesByWorkspace[workspaceID]?.first(where: { $0.id == id }))
    }

    func listJobs(
        workspaceID: String,
        machineID: String?,
        status: FleetRunnerJobStatus?,
        cursor: String?,
        limit: Int?
    ) async throws -> FleetRunnerJobPage {
        if let machineID {
            jobMachineIDs.append(machineID)
        }
        return jobPage
    }
}

@MainActor
private final class SuspendedRunnerPlatformClient: RunnerPlatformLoading {
    let workspace: FleetWorkspace
    let machine: FleetMachine

    private var continuation: CheckedContinuation<[FleetWorkspace], Never>?
    private var hasStarted = false

    init(workspace: FleetWorkspace, machine: FleetMachine) {
        self.workspace = workspace
        self.machine = machine
    }

    func listWorkspaces() async throws -> [FleetWorkspace] {
        hasStarted = true
        return await withCheckedContinuation { continuation in
            self.continuation = continuation
        }
    }

    func listMachines(workspaceID: String) async throws -> [FleetMachine] {
        [machine]
    }

    func getMachine(id: String, workspaceID: String) async throws -> FleetMachine {
        machine
    }

    func listJobs(
        workspaceID: String,
        machineID: String?,
        status: FleetRunnerJobStatus?,
        cursor: String?,
        limit: Int?
    ) async throws -> FleetRunnerJobPage {
        FleetRunnerJobPage(jobs: [], nextCursor: nil)
    }

    func waitUntilStarted() async {
        while !hasStarted {
            await Task.yield()
        }
    }

    func resume() {
        continuation?.resume(returning: [workspace])
        continuation = nil
    }
}
