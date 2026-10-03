import XCTest

@testable import ArcBox

final class KubernetesStateTests: XCTestCase {
    @MainActor
    func testStatusFailureAndCancellationPreserveKnownData() async {
        let client = KubernetesControlClientStub()
        let failedState = KubernetesState(lifecycle: .ready)
        failedState.podsModel.pods = [pod(id: "pod")]
        client.statusHandler = { throw StubError.failed }

        await failedState.checkStatus(client: client)

        guard case .failed(.status, _) = failedState.lifecycle else {
            return XCTFail("Expected a visible status failure")
        }
        XCTAssertEqual(failedState.podsModel.pods.map(\.id), ["pod"])

        let cancelledState = KubernetesState(lifecycle: .ready)
        cancelledState.podsModel.pods = [pod(id: "pod")]
        client.statusHandler = { throw CancellationError() }

        await cancelledState.checkStatus(client: client)

        XCTAssertEqual(cancelledState.lifecycle, .ready)
        XCTAssertEqual(cancelledState.podsModel.pods.map(\.id), ["pod"])
    }

    @MainActor
    func testDisabledStatusClearsBothResourceModels() async {
        let client = KubernetesControlClientStub()
        client.statusHandler = { KubernetesStatus(running: false, apiReady: false) }
        let state = KubernetesState(lifecycle: .ready)
        state.podsModel.pods = [pod(id: "pod")]
        state.podsModel.selectedID = "pod"
        state.servicesModel.services = [service(id: "service")]
        state.servicesModel.selectedID = "service"

        await state.checkStatus(client: client)

        XCTAssertEqual(state.lifecycle, .disabled)
        XCTAssertTrue(state.podsModel.pods.isEmpty)
        XCTAssertNil(state.podsModel.selectedID)
        XCTAssertTrue(state.servicesModel.services.isEmpty)
        XCTAssertNil(state.servicesModel.selectedID)
    }

    @MainActor
    func testStreamSnapshotsTrackFreshnessUntilCleared() throws {
        let pods = PodsViewModel()
        let services = ServicesViewModel()
        let requestedAt = ContinuousClock().now

        pods.apply([])
        services.apply([])

        XCTAssertGreaterThanOrEqual(try XCTUnwrap(pods.lastStreamUpdate), requestedAt)
        XCTAssertGreaterThanOrEqual(try XCTUnwrap(services.lastStreamUpdate), requestedAt)

        pods.clear()
        services.clear()
        XCTAssertNil(pods.lastStreamUpdate)
        XCTAssertNil(services.lastStreamUpdate)
    }

    @MainActor
    func testUnavailableClientAndStopFailureRemainVisible() async {
        let unavailableState = KubernetesState()

        await unavailableState.checkStatus(client: nil)

        guard case .failed(.status, _) = unavailableState.lifecycle else {
            return XCTFail("Expected a visible unavailable-client failure")
        }

        let client = KubernetesControlClientStub()
        client.stopHandler = { throw StubError.failed }
        let stopState = KubernetesState(lifecycle: .ready)
        stopState.podsModel.pods = [pod(id: "pod")]

        await stopState.stop(client: client)

        guard case .failed(.stop, _) = stopState.lifecycle else {
            return XCTFail("Expected a visible stop failure")
        }
        XCTAssertEqual(stopState.podsModel.pods.map(\.id), ["pod"])
    }

    @MainActor
    func testNewStatusCheckSupersedesCancelledCheckForSameClient() async {
        let client = KubernetesControlClientStub()
        let state = KubernetesState()
        var callCount = 0
        client.statusHandler = {
            callCount += 1
            if callCount == 1 {
                try await Task.sleep(for: .seconds(60))
            }
            return KubernetesStatus(running: false, apiReady: false)
        }

        let firstCheck = Task { await state.checkStatus(client: client) }
        while callCount == 0 {
            await Task.yield()
        }
        let replacementCheck = Task { await state.checkStatus(client: client) }
        await replacementCheck.value
        firstCheck.cancel()
        await firstCheck.value

        XCTAssertEqual(callCount, 2)
        XCTAssertEqual(state.lifecycle, .disabled)
    }

    private func pod(id: String) -> PodViewModel {
        PodViewModel(
            id: id,
            name: id,
            namespace: "default",
            phase: .running,
            containerCount: 1,
            readyCount: 1,
            restartCount: 0,
            createdAt: .distantPast
        )
    }

    private func service(id: String) -> ServiceViewModel {
        ServiceViewModel(
            id: id,
            name: id,
            namespace: "default",
            type: .clusterIP,
            clusterIP: "10.0.0.1",
            ports: [],
            createdAt: .distantPast
        )
    }
}

@MainActor
private final class KubernetesControlClientStub: KubernetesControlClient {
    var statusHandler: @MainActor () async throws -> KubernetesStatus = {
        KubernetesStatus(running: false, apiReady: false)
    }
    var startHandler: @MainActor () async throws -> Void = {}
    var stopHandler: @MainActor () async throws -> Void = {}
    var kubeconfigHandler: @MainActor () async throws -> String = { "" }

    func kubernetesStatus() async throws -> KubernetesStatus {
        try await statusHandler()
    }

    func startKubernetes() async throws {
        try await startHandler()
    }

    func stopKubernetes() async throws {
        try await stopHandler()
    }

    func kubernetesKubeconfig() async throws -> String {
        try await kubeconfigHandler()
    }
}

private enum StubError: Error {
    case failed
}
