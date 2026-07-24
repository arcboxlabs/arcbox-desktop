import FleetControlClient
import FleetPlatformClient
import Foundation

nonisolated struct RunnerJobDetailModel: Equatable {
    let id: String
    let repository: String?
    let status: FleetRunnerJobStatus
    let os: String
    let arch: String
    let githubRunID: Int64?
    let githubJobID: Int64?
    let labels: [String]
    let machineID: String?
    let jitRunnerName: String?
    let createdAt: Date?
    let startedAt: Date?
    let finishedAt: Date?

    static func resolve(
        id: String,
        platformJobs: [FleetRunnerJob],
        liveJobs: [FleetInFlightJob]
    ) -> RunnerJobDetailModel? {
        let platformJob = platformJobs.first { $0.id == id }
        let liveJob = liveJobs.first { $0.id == id }

        if let platformJob {
            return RunnerJobDetailModel(
                id: platformJob.id,
                repository: platformJob.repo,
                status: liveJob == nil ? platformJob.status : .running,
                os: platformJob.os.rawValue,
                arch: platformJob.arch.rawValue,
                githubRunID: platformJob.githubRunID,
                githubJobID: platformJob.githubJobID,
                labels: platformJob.labels,
                machineID: platformJob.machineID,
                jitRunnerName: platformJob.jitRunnerName,
                createdAt: platformJob.createdAt,
                startedAt: platformJob.startedAt,
                finishedAt: platformJob.finishedAt
            )
        }

        guard let liveJob else { return nil }
        return RunnerJobDetailModel(
            id: liveJob.id,
            repository: nil,
            status: .running,
            os: liveJob.os,
            arch: liveJob.arch,
            githubRunID: nil,
            githubJobID: nil,
            labels: [],
            machineID: nil,
            jitRunnerName: nil,
            createdAt: nil,
            startedAt: nil,
            finishedAt: nil
        )
    }

    var githubURL: URL? {
        guard
            let repository,
            let githubRunID,
            let githubJobID
        else {
            return nil
        }

        let repositoryComponents = repository.split(separator: "/", omittingEmptySubsequences: false)
        guard
            repositoryComponents.count == 2,
            repositoryComponents.allSatisfy({ !$0.isEmpty })
        else {
            return nil
        }

        var components = URLComponents()
        components.scheme = "https"
        components.host = "github.com"
        components.path =
            "/\(repositoryComponents[0])/\(repositoryComponents[1])"
            + "/actions/runs/\(githubRunID)/job/\(githubJobID)"
        return components.url
    }

    var runtimeKind: String {
        switch os {
        case "darwin", "macos":
            "Virtual machine"
        case "linux":
            "Docker container"
        default:
            "Runtime"
        }
    }

    var runtimeUnavailableDescription: String {
        switch os {
        case "darwin", "macos":
            "The current job contract does not report the VZ virtual machine ID, so ArcBox cannot open this runtime in Machines."
        case "linux":
            "The current job contract does not report the Docker container ID, so ArcBox cannot open this runtime in Containers."
        default:
            "The current job contract does not report a runtime resource ID."
        }
    }
}
