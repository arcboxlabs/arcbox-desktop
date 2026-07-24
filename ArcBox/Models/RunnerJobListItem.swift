import FleetControlClient
import FleetPlatformClient

nonisolated struct RunnerJobListItem: Identifiable, Equatable {
    let id: String
    let repository: String?
    let os: String
    let arch: String
    let status: FleetRunnerJobStatus

    static func merge(
        platformJobs: [FleetRunnerJob],
        liveJobs: [FleetInFlightJob]
    ) -> [RunnerJobListItem] {
        let liveIDs = Set(liveJobs.map(\.id))
        let platformIDs = Set(platformJobs.map(\.id))

        let liveOnly =
            liveJobs
            .filter { !platformIDs.contains($0.id) }
            .map {
                RunnerJobListItem(
                    id: $0.id,
                    repository: nil,
                    os: $0.os,
                    arch: $0.arch,
                    status: .running
                )
            }
        let platformItems = platformJobs.map {
            RunnerJobListItem(
                id: $0.id,
                repository: $0.repo,
                os: $0.os.rawValue,
                arch: $0.arch.rawValue,
                status: liveIDs.contains($0.id) ? .running : $0.status
            )
        }

        return liveOnly + platformItems
    }
}
