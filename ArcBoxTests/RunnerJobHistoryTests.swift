import FleetPlatformClient
import XCTest

@testable import ArcBox

@MainActor
final class RunnerJobHistoryTests: XCTestCase {
    func testLoadsJobsBeyondTheFirstFifty() async {
        let client = PagedRunnerHistoryClient(count: 51)
        let store = RunnerPlatformStore()
        await store.refresh(client: client, machineID: client.machine.id)
        XCTAssertEqual(store.jobs.count, 50)

        await store.loadMore(client: client)

        XCTAssertEqual(store.jobs, client.jobs)
        XCTAssertNil(store.nextCursor)
        XCTAssertFalse(store.isLoadingMore)
        XCTAssertEqual(client.cursors, [nil, PagedRunnerHistoryClient.jobID(2)])
    }

    func testRefreshPreservesExpandedHistoryAndSelectionWithoutLoadingAllHistory() async throws {
        let client = PagedRunnerHistoryClient(count: 300)
        let store = RunnerPlatformStore()
        await store.refresh(client: client, machineID: client.machine.id)
        await store.loadMore(client: client)
        let selectedID = try XCTUnwrap(store.jobs.last?.id)
        store.selectJob(id: selectedID)

        client.jobs = (1...302).reversed().map {
            PagedRunnerHistoryClient.job($0, status: $0 == 250 ? .failed : .completed)
        }
        await store.refresh(client: client, machineID: client.machine.id)
        store.reconcileSelection(validJobIDs: Set(store.jobs.map(\.id)))

        XCTAssertEqual(store.selectedJobID, selectedID)
        XCTAssertEqual(store.jobs.count, 150)
        XCTAssertEqual(store.jobs.first(where: { $0.id == PagedRunnerHistoryClient.jobID(250) })?.status, .failed)
        XCTAssertNotNil(store.nextCursor)
        XCTAssertFalse(store.jobs.contains { $0.id == PagedRunnerHistoryClient.jobID(1) })

        client.jobs.insert(PagedRunnerHistoryClient.job(303), at: 0)
        await store.refresh(client: client, machineID: client.machine.id)
        XCTAssertEqual(store.jobs.count, 150, "A poll must not expand the requested history boundary.")

        let roundedPageSelection = try XCTUnwrap(store.jobs.last?.id)
        client.jobs.insert(PagedRunnerHistoryClient.job(304), at: 0)
        let gate = HistoryPageGate()
        client.beforePage = { await gate.suspend() }
        let refresh = Task { await store.refresh(client: client, machineID: client.machine.id) }
        await gate.waitUntilStarted()
        store.selectJob(id: roundedPageSelection)
        client.beforePage = nil
        gate.resume()
        await refresh.value
        store.reconcileSelection(validJobIDs: Set(store.jobs.map(\.id)))
        XCTAssertEqual(store.selectedJobID, roundedPageSelection)
    }

    func testPageFailurePreservesHistoryAndCanRetryTheSameCursor() async {
        let client = PagedRunnerHistoryClient(count: 51)
        let store = RunnerPlatformStore()
        await store.refresh(client: client, machineID: client.machine.id)
        let originalJobs = store.jobs
        let cursor = store.nextCursor
        client.beforePage = { throw URLError(.networkConnectionLost) }

        await store.loadMore(client: client)

        XCTAssertEqual(store.jobs, originalJobs)
        XCTAssertEqual(store.nextCursor, cursor)
        XCTAssertFalse(store.isLoadingMore)
        guard case .failed = store.loadState else {
            return XCTFail("The page error must remain visible.")
        }

        client.beforePage = nil
        await store.loadMore(client: client)
        XCTAssertEqual(store.jobs, client.jobs)
        XCTAssertEqual(store.loadState, .loaded)
        XCTAssertEqual(client.cursors, [nil, cursor, cursor])
    }

    func testResetDiscardsAnInFlightPageAndBlocksDuplicateRequests() async {
        let client = PagedRunnerHistoryClient(count: 51)
        let store = RunnerPlatformStore()
        await store.refresh(client: client, machineID: client.machine.id)
        let gate = HistoryPageGate()
        client.beforePage = { await gate.suspend() }
        let pending = Task { await store.loadMore(client: client) }
        await gate.waitUntilStarted()

        await store.loadMore(client: client)
        XCTAssertEqual(client.cursors.count, 2)
        store.reset()
        gate.resume()
        await pending.value

        XCTAssertTrue(store.jobs.isEmpty)
        XCTAssertNil(store.nextCursor)
        XCTAssertFalse(store.isLoadingMore)
        XCTAssertEqual(store.loadState, .idle)
    }

    func testLatePageCannotAppendJobsToAnotherMachine() async {
        let oldClient = PagedRunnerHistoryClient(count: 51)
        let newClient = PagedRunnerHistoryClient(count: 3, machineID: "machine-b")
        let store = RunnerPlatformStore()
        await store.refresh(client: oldClient, machineID: oldClient.machine.id)
        let gate = HistoryPageGate()
        oldClient.beforePage = { await gate.suspend() }
        let pending = Task { await store.loadMore(client: oldClient) }
        await gate.waitUntilStarted()

        await store.refresh(client: newClient, machineID: newClient.machine.id)
        gate.resume()
        await pending.value

        XCTAssertEqual(store.machine, newClient.machine)
        XCTAssertEqual(store.jobs, newClient.jobs)
        XCTAssertNil(store.nextCursor)
        XCTAssertFalse(store.isLoadingMore)
    }
}

@MainActor
private final class PagedRunnerHistoryClient: RunnerPlatformLoading {
    let workspace = FleetWorkspace(
        id: "workspace", name: "Team", plan: "free", createdAt: .distantPast, updatedAt: .distantPast)
    let machine: FleetMachine
    var jobs: [FleetRunnerJob]
    var beforePage: (() async throws -> Void)?
    private(set) var cursors: [String?] = []

    init(count: Int, machineID: String = "machine-a") {
        machine = FleetMachine(
            id: machineID, name: machineID, status: .online, arch: "arm64", cpu: 8, memMib: 16_384,
            tags: [], createdAt: .distantPast, enrolledAt: .distantPast, lastSeen: .distantPast,
            agentVersion: "0.8.2", pools: [], telemetry: nil
        )
        jobs = (1...count).reversed().map { Self.job($0, machineID: machineID) }
    }

    func listWorkspaces() async throws -> [FleetWorkspace] { [workspace] }
    func listMachines(workspaceID: String) async throws -> [FleetMachine] { [machine] }
    func getMachine(id: String, workspaceID: String) async throws -> FleetMachine { machine }

    func listJobs(
        workspaceID: String, machineID: String?, status: FleetRunnerJobStatus?, cursor: String?, limit: Int?
    ) async throws -> FleetRunnerJobPage {
        XCTAssertEqual(workspaceID, workspace.id)
        XCTAssertEqual(machineID, machine.id)
        XCTAssertNil(status)
        XCTAssertEqual(limit, 50)
        cursors.append(cursor)
        try await beforePage?()
        let candidates = cursor.map { cursor in jobs.filter { $0.id < cursor } } ?? jobs
        let page = Array(candidates.prefix(try XCTUnwrap(limit)))
        return FleetRunnerJobPage(jobs: page, nextCursor: candidates.count > page.count ? page.last?.id : nil)
    }

    static func jobID(_ number: Int) -> String {
        String(format: "rjob_00000000-0000-7000-8000-%012x", number)
    }

    static func job(
        _ number: Int, machineID: String = "machine-a", status: FleetRunnerJobStatus = .completed
    ) -> FleetRunnerJob {
        FleetRunnerJob(
            id: jobID(number), repo: "arcboxlabs/arcbox", status: status, os: .darwin, arch: .arm64,
            githubRunID: 1, githubJobID: Int64(number), labels: [], machineID: machineID, jitRunnerName: nil,
            createdAt: .distantPast, startedAt: .distantPast, finishedAt: .distantPast
        )
    }
}

@MainActor
private final class HistoryPageGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func suspend() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func waitUntilStarted() async {
        while continuation == nil { await Task.yield() }
    }

    func resume() {
        continuation?.resume()
        continuation = nil
    }
}
