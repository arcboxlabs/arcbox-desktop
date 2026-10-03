import ArcBoxClient
import GRPCCore
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
        XCTAssertTrue(model.migrationMayBeRunning)

        continuation.yield(completionEvent)
        await termination.value
        XCTAssertTrue(terminationFinished)
        XCTAssertFalse(model.migrationMayBeRunning)
        let completed = model.state
        await model.loadPreview()
        model.startMigration()
        XCTAssertEqual(model.state, completed)
        XCTAssertEqual(prepareCount, 2)
    }

    func testTerminationStopsReconnectsWithoutDeclaringMigrationFinished() async {
        for terminateDuringBackoff in [false, true] {
            let streamStarted = expectation(description: "Migration stream started")
            let terminationFinished = expectation(description: "Termination finished")
            let disconnectGate = MigrationTestGate()
            var streamCount = 0
            let model = OnboardingMigrationModel(
                detectSource: { self.source },
                prepareMigration: { self.response(for: $0) },
                runMigrationStream: { _, receive in
                    streamCount += 1
                    if streamCount == 1 {
                        streamStarted.fulfill()
                        if !terminateDuringBackoff {
                            await disconnectGate.wait()
                        }
                        throw RPCError(code: .unavailable, message: "Runtime disconnected")
                    }
                    receive(self.completionEvent)
                    return true
                }
            )
            await model.loadPreview()
            model.startMigration()
            await fulfillment(of: [streamStarted], timeout: 2)
            if terminateDuringBackoff {
                guard case .migrating(_, let progress) = model.state else {
                    XCTFail("An unavailable runtime must enter reconnect backoff.")
                    return
                }
                XCTAssertEqual(progress.phase, "reconnecting")
            }

            model.beginTermination()
            let termination = Task {
                await model.waitForCompletion()
                terminationFinished.fulfill()
            }
            disconnectGate.open()
            await fulfillment(of: [terminationFinished], timeout: 5)
            await termination.value

            XCTAssertEqual(streamCount, 1)
            XCTAssertTrue(model.migrationMayBeRunning)
            guard case .failed(_, let message) = model.state else {
                XCTFail("A disconnected migration must not report completion.")
                return
            }
            XCTAssertTrue(message.contains("runtime will stay running"))
        }
    }

    func testMigrationReconnectsToTheSamePlanAndConfirmsCompletion() async {
        var planIDs: [String] = []
        let model = OnboardingMigrationModel(
            detectSource: { self.source },
            prepareMigration: { self.response(for: $0) },
            runMigrationStream: { request, receive in
                planIDs.append(request.planID)
                if planIDs.count == 1 {
                    throw RPCError(code: .unavailable, message: "Runtime disconnected")
                }
                receive(self.completionEvent)
                return true
            }
        )
        await model.loadPreview()
        model.startMigration()
        await model.waitForCompletion()

        XCTAssertEqual(planIDs, ["reviewed-plan", "reviewed-plan"])
        XCTAssertFalse(model.migrationMayBeRunning)
        guard case .completed = model.state else {
            XCTFail("A recovered stream must complete the original migration.")
            return
        }
    }

    func testDaemonRestartConfirmsTheMigrationIsNoLongerRunning() async {
        let model = OnboardingMigrationModel(
            detectSource: { self.source },
            prepareMigration: { self.response(for: $0) },
            runMigrationStream: { _, _ in
                throw RPCError(code: .notFound, message: "Migration plan not found")
            }
        )
        await model.loadPreview()
        model.startMigration()
        await model.waitForCompletion()

        XCTAssertFalse(model.migrationMayBeRunning)
        guard case .failed(_, let message) = model.state else {
            XCTFail("A missing plan after a daemon restart must fail migration.")
            return
        }
        XCTAssertTrue(message.contains("daemon restarted"))
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

    func testChangedReplacementTargetsDoNotRunUntilTheNewPreviewIsConfirmed() async {
        var previewCount = 0
        var executionCount = 0
        var executedPlanIDs: [String] = []
        let model = OnboardingMigrationModel(
            detectSource: { self.source },
            prepareMigration: { request in
                var response = self.response(for: request)
                response.volumeCount = 2
                response.replacementsRequired = true
                if request.dryRun {
                    previewCount += 1
                    response.replacements.volumes = previewCount == 1 ? ["data-a"] : ["data-a", "data-b"]
                    response.plan.replacements = response.replacements
                } else {
                    executionCount += 1
                    response.replacements.volumes = ["data-b", "data-a"]
                    response.planID = "prepared-\(executionCount)"
                }
                return response
            },
            runMigrationStream: { request, receive in
                executedPlanIDs.append(request.planID)
                receive(self.completionEvent)
                return true
            }
        )
        await model.loadPreview()
        model.startMigration()
        await model.waitForCompletion()

        XCTAssertTrue(executedPlanIDs.isEmpty)
        guard case .failed(nil, _) = model.state else {
            XCTFail("A changed replacement target must invalidate the approved preview.")
            return
        }

        await model.loadPreview()
        guard case .review(let updatedPreview) = model.state else {
            XCTFail("A new preview must be available for confirmation.")
            return
        }
        XCTAssertEqual(updatedPreview.replacements.volumes, ["data-a", "data-b"])
        XCTAssertTrue(executedPlanIDs.isEmpty)
        model.startMigration()
        await model.waitForCompletion()

        XCTAssertEqual(executedPlanIDs, ["prepared-2"])
        guard case .completed = model.state else {
            XCTFail("The migration must run the plan whose replacement targets were confirmed.")
            return
        }
    }

    func testMissingReplacementSummaryInEitherPreparePreventsExecution() async {
        for missingFromPreview in [true, false] {
            var prepareCount = 0
            let model = OnboardingMigrationModel(
                detectSource: { self.source },
                prepareMigration: { request in
                    prepareCount += 1
                    var response = self.response(for: request)
                    if request.dryRun == missingFromPreview {
                        response.clearReplacements()
                    }
                    return response
                },
                runMigrationStream: { _, _ in
                    XCTFail("A daemon without a replacement summary must not execute the migration.")
                    return true
                }
            )
            await model.loadPreview()
            model.startMigration()
            await model.waitForCompletion()

            XCTAssertEqual(prepareCount, missingFromPreview ? 1 : 2)
            guard case .failed(nil, let message) = model.state else {
                XCTFail("A missing replacement summary must block migration.")
                return
            }
            XCTAssertTrue(message.contains("Update and restart ArcBox"))
        }
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
        response.replacements = .init()
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
