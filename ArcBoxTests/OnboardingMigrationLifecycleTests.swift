import ArcBoxClient
import XCTest

@testable import ArcBox

@MainActor
final class OnboardingMigrationLifecycleTests: XCTestCase {
    func testPreviewReloadPreservesPreparingAndMigratingSession() async {
        let prepareStarted = expectation(description: "Execution prepare started")
        let streamStarted = expectation(description: "Migration stream started")
        let prepareGate = MigrationTestGate()
        let (events, continuation) = AsyncStream<Arcbox_V1_RunMigrationEvent>.makeStream()
        var detectionCount = 0
        var prepareCount = 0
        let model = OnboardingMigrationModel(
            detectSource: {
                detectionCount += 1
                return self.source
            },
            prepareMigration: { request in
                prepareCount += 1
                if !request.dryRun {
                    prepareStarted.fulfill()
                    await prepareGate.wait()
                }
                return self.response(for: request)
            },
            runMigrationStream: { _, receive in
                streamStarted.fulfill()
                for await event in events {
                    receive(event)
                    if event.done { return true }
                }
                return false
            }
        )
        await model.loadPreview()
        model.startMigration()
        await fulfillment(of: [prepareStarted], timeout: 2)

        let preparing = model.state
        await model.loadPreview()
        XCTAssertEqual(model.state, preparing)
        XCTAssertTrue(model.state.isExecuting)
        XCTAssertEqual(detectionCount, 1)
        XCTAssertEqual(prepareCount, 2)

        prepareGate.open()
        await fulfillment(of: [streamStarted], timeout: 2)
        let migrating = model.state
        await model.loadPreview()
        model.startMigration()
        XCTAssertEqual(model.state, migrating)
        XCTAssertEqual(detectionCount, 1)
        XCTAssertEqual(prepareCount, 2)

        continuation.yield(completionEvent)
        await model.waitForCompletion()
        guard case .completed = model.state else {
            XCTFail("The original migration must reach its terminal event.")
            return
        }
    }

    func testTerminationWaitsThroughPrepareAndStreamCompletion() async {
        let prepareStarted = expectation(description: "Execution prepare started")
        let streamStarted = expectation(description: "Migration stream started")
        let waiterStarted = expectation(description: "Termination waiter started")
        let prepareGate = MigrationTestGate()
        let (events, continuation) = AsyncStream<Arcbox_V1_RunMigrationEvent>.makeStream()
        var prepareCount = 0
        var terminationFinished = false
        let model = OnboardingMigrationModel(
            detectSource: { self.source },
            prepareMigration: { request in
                prepareCount += 1
                if !request.dryRun {
                    prepareStarted.fulfill()
                    await prepareGate.wait()
                }
                return self.response(for: request)
            },
            runMigrationStream: { request, receive in
                XCTAssertEqual(request.planID, "reviewed-plan")
                streamStarted.fulfill()
                for await event in events {
                    receive(event)
                    if event.done { return true }
                }
                return false
            }
        )
        await model.loadPreview()
        model.startMigration()
        await fulfillment(of: [prepareStarted], timeout: 2)

        model.beginTermination()
        let termination = Task {
            waiterStarted.fulfill()
            await model.waitForCompletion()
            terminationFinished = true
        }
        await fulfillment(of: [waiterStarted], timeout: 2)
        XCTAssertFalse(terminationFinished)

        prepareGate.open()
        await fulfillment(of: [streamStarted], timeout: 2)
        XCTAssertFalse(terminationFinished)

        continuation.yield(completionEvent)
        await termination.value
        XCTAssertTrue(terminationFinished)
        let completed = model.state
        await model.loadPreview()
        model.startMigration()
        XCTAssertEqual(model.state, completed)
        XCTAssertEqual(prepareCount, 2)
    }

    func testPreviewSurvivesViewCancellationAndSharesPendingRequest() async {
        let detectionStarted = expectation(description: "Source detection started")
        let secondViewStarted = expectation(description: "Second view requested the preview")
        let detectionGate = MigrationTestGate()
        var detectionCount = 0
        let model = OnboardingMigrationModel(
            detectSource: {
                detectionCount += 1
                detectionStarted.fulfill()
                await detectionGate.wait()
                try Task.checkCancellation()
                return self.source
            },
            prepareMigration: { self.response(for: $0) },
            runMigrationStream: { _, _ in
                XCTFail("Loading a preview must not start a migration.")
                return true
            }
        )
        let firstView = Task { await model.loadPreview() }
        await fulfillment(of: [detectionStarted], timeout: 2)
        firstView.cancel()
        let secondView = Task {
            secondViewStarted.fulfill()
            await model.loadPreview()
        }
        await fulfillment(of: [secondViewStarted], timeout: 2)

        detectionGate.open()
        await firstView.value
        await secondView.value
        XCTAssertEqual(detectionCount, 1)
        guard case .review = model.state else {
            XCTFail("The shared preview must remain usable after its original view closes.")
            return
        }
    }

    func testTerminationRejectsMigrationFromAnExistingPreview() async {
        var prepareCount = 0
        let model = OnboardingMigrationModel(
            detectSource: { self.source },
            prepareMigration: { request in
                prepareCount += 1
                return self.response(for: request)
            },
            runMigrationStream: { _, _ in
                XCTFail("Termination must prevent a new migration.")
                return true
            }
        )
        await model.loadPreview()
        let reviewed = model.state
        model.beginTermination()
        model.startMigration()
        await model.waitForCompletion()
        XCTAssertEqual(model.state, reviewed)
        XCTAssertEqual(prepareCount, 1)
    }

    private var source: DockerMigrationSource {
        DockerMigrationSource(
            kind: .orbStack,
            contextName: "orbstack",
            socketPath: "/tmp/orbstack-test.sock"
        )
    }

    private func response(
        for request: Arcbox_V1_PrepareMigrationRequest
    ) -> Arcbox_V1_PrepareMigrationResponse {
        var response = Arcbox_V1_PrepareMigrationResponse()
        response.sourceKind = request.sourceKind
        response.sourceSocketPath = request.sourceSocketPath
        response.imageCount = 1
        if request.dryRun {
            response.plan.source.daemonName = "OrbStack"
        } else {
            response.planID = "reviewed-plan"
        }
        return response
    }

    private var completionEvent: Arcbox_V1_RunMigrationEvent {
        var event = Arcbox_V1_RunMigrationEvent()
        event.done = true
        event.success = true
        return event
    }
}

@MainActor
private final class MigrationTestGate {
    private var continuation: CheckedContinuation<Void, Never>?

    func wait() async {
        await withCheckedContinuation { continuation = $0 }
    }

    func open() {
        continuation?.resume()
        continuation = nil
    }
}
