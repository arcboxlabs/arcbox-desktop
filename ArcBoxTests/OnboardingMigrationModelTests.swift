import ArcBoxClient
import GRPCCore
import XCTest

@testable import ArcBox

@MainActor
final class OnboardingMigrationModelTests: XCTestCase {
    func testReconnectsOnlyForUnavailableRPCs() {
        XCTAssertTrue(OnboardingMigrationModel.shouldReconnect(after: .unavailable))
        XCTAssertFalse(OnboardingMigrationModel.shouldReconnect(after: .internalError))
        XCTAssertFalse(OnboardingMigrationModel.shouldReconnect(after: .invalidArgument))
        XCTAssertFalse(OnboardingMigrationModel.shouldReconnect(after: .failedPrecondition))
    }

    func testMatchingPrepareResponseDoesNotRequireThePreviewPlan() {
        let (preview, prepared) = makePreviewAndPreparedResponse()

        XCTAssertTrue(preview.stopsSourceContainers)
        XCTAssertFalse(prepared.hasPlan)
        XCTAssertTrue(preview.matches(prepared))
    }

    func testWarningOrderDoesNotChangeTheApprovedPreview() {
        let (preview, prepared) = makePreviewAndPreparedResponse()
        var reordered = prepared
        reordered.warnings.reverse()

        XCTAssertTrue(preview.matches(reordered))
    }

    func testNewSourceContainerStopWarningRequiresAnotherPreview() {
        let (preview, prepared) = makePreviewAndPreparedResponse(stopsSourceContainers: false)
        var changed = prepared
        changed.warnings.append("volume 'data' is attached to running source containers: database")

        XCTAssertFalse(preview.matches(changed))
    }

    func testChangedSourceContainerStopWarningRequiresAnotherPreview() {
        let (preview, prepared) = makePreviewAndPreparedResponse()
        var changed = prepared
        changed.warnings[0] = "volume 'data' is attached to running source containers: database, worker"

        XCTAssertFalse(preview.matches(changed))
    }

    func testChangedSourceKindOrSocketRequiresAnotherPreview() {
        let (preview, prepared) = makePreviewAndPreparedResponse()
        var changedKind = prepared
        changedKind.sourceKind = DockerMigrationSource.Kind.dockerDesktop.rawValue
        var changedSocket = prepared
        changedSocket.sourceSocketPath = "/Users/test/.docker/run/docker.sock"

        XCTAssertFalse(preview.matches(changedKind))
        XCTAssertFalse(preview.matches(changedSocket))
    }

    func testChangedResourceCountsRequireAnotherPreview() {
        let (preview, prepared) = makePreviewAndPreparedResponse()
        let counts: [(String, WritableKeyPath<Arcbox_V1_PrepareMigrationResponse, UInt32>)] = [
            ("images", \.imageCount),
            ("volumes", \.volumeCount),
            ("networks", \.networkCount),
            ("containers", \.containerCount),
        ]

        for (resource, count) in counts {
            var changed = prepared
            changed[keyPath: count] += 1
            XCTAssertFalse(preview.matches(changed), "Changed \(resource) count must require another preview.")
        }
    }

    func testNewReplacementRequirementRequiresAnotherPreview() {
        let (preview, prepared) = makePreviewAndPreparedResponse()
        var changed = prepared
        changed.replacementsRequired = true

        XCTAssertFalse(preview.matches(changed))
    }

    func testChangedReplacementTargetsRequireAnotherPreviewWithTheSameCountsAndWarnings() {
        let (preview, prepared) = makePreviewAndPreparedResponse(replacements: replacementSummary)
        let resources: [(String, WritableKeyPath<Arcbox_V1_MigrationReplacementSummary, [String]>)] = [
            ("containers", \.containers),
            ("volumes", \.volumes),
            ("networks", \.networks),
            ("image tags", \.imageTags),
        ]

        for (resource, names) in resources {
            var added = prepared
            added.replacements[keyPath: names].append("new-target")
            XCTAssertFalse(preview.matches(added), "Additional \(resource) must require another preview.")

            var renamed = prepared
            renamed.replacements[keyPath: names][0] = "different-target"
            XCTAssertFalse(preview.matches(renamed), "Different \(resource) must require another preview.")

            var removed = prepared
            removed.replacements[keyPath: names].removeLast()
            XCTAssertFalse(preview.matches(removed), "Removed \(resource) must require another preview.")
        }
    }

    func testReplacementOrderDoesNotChangeTheApprovedPreview() {
        let (preview, prepared) = makePreviewAndPreparedResponse(replacements: replacementSummary)
        var reordered = prepared
        reordered.replacements.containers.reverse()
        reordered.replacements.volumes.reverse()
        reordered.replacements.networks.reverse()
        reordered.replacements.imageTags.reverse()

        XCTAssertTrue(preview.matches(reordered))
    }

    func testMissingReplacementSummaryCannotMatchEvenWhenNoReplacementsAreRequired() {
        for replacements in [Arcbox_V1_MigrationReplacementSummary(), replacementSummary] {
            let (preview, prepared) = makePreviewAndPreparedResponse(replacements: replacements)
            var missingSummary = prepared
            missingSummary.clearReplacements()

            XCTAssertFalse(preview.matches(missingSummary))
        }
    }

    func testConfirmationNamesTargetResourcesAndWarnsAboutExistingVolumeData() {
        var replacements = Arcbox_V1_MigrationReplacementSummary()
        replacements.containers = ["database", "worker"]
        replacements.volumes = ["postgres-data", "cache"]
        replacements.networks = ["app"]
        replacements.imageTags = ["postgres:16"]
        let (preview, prepared) = makePreviewAndPreparedResponse(
            stopsSourceContainers: false,
            replacements: replacements
        )

        XCTAssertEqual(
            preview.confirmationMessages,
            [
                "ArcBox containers will be replaced: database, worker.",
                "Existing ArcBox volume data will be replaced: postgres-data, cache.",
                "ArcBox networks will be replaced: app.",
                "ArcBox image tags will be replaced: postgres:16.",
            ]
        )
        XCTAssertFalse(prepared.hasPlan)
        XCTAssertTrue(preview.matches(prepared))
    }

    func testNoReplacementsNeedNoReplacementConfirmation() {
        let (preview, _) = makePreviewAndPreparedResponse(stopsSourceContainers: false)
        let (stoppingPreview, _) = makePreviewAndPreparedResponse()

        XCTAssertTrue(preview.confirmationMessages.isEmpty)
        XCTAssertEqual(
            stoppingPreview.confirmationMessages,
            ["Source containers using migrated volumes will be stopped."]
        )
    }

    private func makePreviewAndPreparedResponse(
        stopsSourceContainers: Bool = true,
        replacements: Arcbox_V1_MigrationReplacementSummary = .init()
    ) -> (
        OnboardingMigrationPreview, Arcbox_V1_PrepareMigrationResponse
    ) {
        let source = DockerMigrationSource(
            kind: .orbStack,
            contextName: "orbstack",
            socketPath: "/Users/test/.orbstack/run/docker.sock"
        )
        var dryRun = Arcbox_V1_PrepareMigrationResponse()
        dryRun.sourceKind = source.kind.rawValue
        dryRun.sourceSocketPath = source.socketPath
        dryRun.imageCount = 1
        dryRun.volumeCount = 2
        dryRun.networkCount = 1
        dryRun.containerCount = 2
        dryRun.plan.source.kind = source.kind.rawValue
        dryRun.plan.source.socketPath = source.socketPath
        dryRun.plan.source.daemonName = "orbstack"
        dryRun.plan.source.serverVersion = "28.3.3"
        dryRun.plan.replacements = replacements
        dryRun.replacements = replacements
        dryRun.replacementsRequired =
            !replacements.containers.isEmpty
            || !replacements.volumes.isEmpty
            || !replacements.networks.isEmpty
            || !replacements.imageTags.isEmpty
        if stopsSourceContainers {
            var databaseBlocker = Arcbox_V1_MigrationRunningVolumeBlocker()
            databaseBlocker.volumeName = "data"
            databaseBlocker.containers = ["database"]
            var cacheBlocker = Arcbox_V1_MigrationRunningVolumeBlocker()
            cacheBlocker.volumeName = "cache"
            cacheBlocker.containers = ["redis"]
            dryRun.plan.blockers = [databaseBlocker, cacheBlocker]
            dryRun.warnings = [
                "volume 'data' is attached to running source containers: database",
                "volume 'cache' is attached to running source containers: redis",
            ]
        }
        let preview = OnboardingMigrationPreview(source: source, response: dryRun)
        var prepared = dryRun
        // The daemon returns the full plan only for dry-run previews.
        prepared.clearPlan()
        prepared.planID = "prepared-migration"
        return (preview, prepared)
    }

    private var replacementSummary: Arcbox_V1_MigrationReplacementSummary {
        var summary = Arcbox_V1_MigrationReplacementSummary()
        summary.containers = ["database", "worker"]
        summary.volumes = ["postgres-data", "cache"]
        summary.networks = ["app", "internal"]
        summary.imageTags = ["postgres:16", "redis:7"]
        return summary
    }
}
