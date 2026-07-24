import Foundation

/// A Platform workspace available to the signed-in user.
public struct FleetWorkspace: Codable, Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let plan: String
    public let createdAt: Date
    public let updatedAt: Date

    public init(id: String, name: String, plan: String, createdAt: Date, updatedAt: Date) {
        self.id = id
        self.name = name
        self.plan = plan
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

/// Short-lived Platform credential presented once to the local Fleet Agent.
public struct FleetEnrollmentToken: Codable, Sendable, Equatable {
    public let token: String
    public let expiresAt: Date

    public init(token: String, expiresAt: Date) {
        self.token = token
        self.expiresAt = expiresAt
    }
}

/// Lifecycle state reported by the Platform for an enrolled Fleet machine.
public enum FleetMachineStatus: String, Decodable, Sendable, Equatable {
    case enrolled
    case online
    case offline
    case draining
    case decommissioned
}

/// Operating system targeted by a runner job or served by a machine pool.
public enum FleetRunnerOS: String, Decodable, Sendable, Equatable {
    case darwin
    case linux
    case windows
}

/// CPU architecture targeted by a runner job or served by a machine pool.
public enum FleetRunnerArchitecture: String, Decodable, Sendable, Equatable {
    case arm64
    case amd64
}

/// Execution backend serving a machine pool.
public enum FleetRunnerBackend: String, Decodable, Sendable, Equatable {
    case hostRunner = "host_runner"
    case docker
    case vm
}

/// One runner capability advertised by a Fleet machine.
public struct FleetMachinePool: Decodable, Sendable, Equatable {
    public let os: FleetRunnerOS
    public let arch: FleetRunnerArchitecture
    public let backedBy: FleetRunnerBackend

    public init(
        os: FleetRunnerOS,
        arch: FleetRunnerArchitecture,
        backedBy: FleetRunnerBackend
    ) {
        self.os = os
        self.arch = arch
        self.backedBy = backedBy
    }
}

/// Latest host utilization snapshot received by the Platform.
public struct FleetMachineTelemetry: Decodable, Sendable, Equatable {
    public let loadAvg1m: Double
    public let cpuCount: Int
    public let memTotalMib: Int64
    public let memAvailableMib: Int64

    public init(
        loadAvg1m: Double,
        cpuCount: Int,
        memTotalMib: Int64,
        memAvailableMib: Int64
    ) {
        self.loadAvg1m = loadAvg1m
        self.cpuCount = cpuCount
        self.memTotalMib = memTotalMib
        self.memAvailableMib = memAvailableMib
    }

    // Keys match the names produced by JSONDecoder.convertFromSnakeCase.
    private enum CodingKeys: String, CodingKey {
        case loadAvg1m = "loadAvg1M"
        case cpuCount
        case memTotalMib
        case memAvailableMib
    }
}

/// A machine enrolled in a Platform workspace.
public struct FleetMachine: Decodable, Identifiable, Sendable, Equatable {
    public let id: String
    public let name: String
    public let status: FleetMachineStatus
    public let arch: String
    public let cpu: Int
    public let memMib: Int64
    public let tags: [String]
    public let createdAt: Date
    public let enrolledAt: Date?
    public let lastSeen: Date?
    public let agentVersion: String?
    public let pools: [FleetMachinePool]
    public let telemetry: FleetMachineTelemetry?

    public init(
        id: String,
        name: String,
        status: FleetMachineStatus,
        arch: String,
        cpu: Int,
        memMib: Int64,
        tags: [String],
        createdAt: Date,
        enrolledAt: Date?,
        lastSeen: Date?,
        agentVersion: String?,
        pools: [FleetMachinePool],
        telemetry: FleetMachineTelemetry?
    ) {
        self.id = id
        self.name = name
        self.status = status
        self.arch = arch
        self.cpu = cpu
        self.memMib = memMib
        self.tags = tags
        self.createdAt = createdAt
        self.enrolledAt = enrolledAt
        self.lastSeen = lastSeen
        self.agentVersion = agentVersion
        self.pools = pools
        self.telemetry = telemetry
    }
}

/// Lifecycle state reported by the Platform for a runner job.
public enum FleetRunnerJobStatus: String, Decodable, Sendable, Equatable {
    case queued
    case provisioning
    case running
    case completed
    case failed
    case canceled
}

/// A GitHub Actions runner job recorded by the Platform.
public struct FleetRunnerJob: Decodable, Identifiable, Sendable, Equatable {
    public let id: String
    public let repo: String
    public let status: FleetRunnerJobStatus
    public let os: FleetRunnerOS
    public let arch: FleetRunnerArchitecture
    public let githubRunID: Int64
    public let githubJobID: Int64
    public let labels: [String]
    public let machineID: String?
    public let jitRunnerName: String?
    public let createdAt: Date
    public let startedAt: Date?
    public let finishedAt: Date?

    public init(
        id: String,
        repo: String,
        status: FleetRunnerJobStatus,
        os: FleetRunnerOS,
        arch: FleetRunnerArchitecture,
        githubRunID: Int64,
        githubJobID: Int64,
        labels: [String],
        machineID: String?,
        jitRunnerName: String?,
        createdAt: Date,
        startedAt: Date?,
        finishedAt: Date?
    ) {
        self.id = id
        self.repo = repo
        self.status = status
        self.os = os
        self.arch = arch
        self.githubRunID = githubRunID
        self.githubJobID = githubJobID
        self.labels = labels
        self.machineID = machineID
        self.jitRunnerName = jitRunnerName
        self.createdAt = createdAt
        self.startedAt = startedAt
        self.finishedAt = finishedAt
    }

    // Keys match the names produced by JSONDecoder.convertFromSnakeCase.
    private enum CodingKeys: String, CodingKey {
        case id
        case repo
        case status
        case os
        case arch
        case githubRunID = "ghRunId"
        case githubJobID = "ghJobId"
        case labels
        case machineID = "machineId"
        case jitRunnerName
        case createdAt
        case startedAt
        case finishedAt
    }
}

/// One cursor-based page of runner jobs.
public struct FleetRunnerJobPage: Decodable, Sendable, Equatable {
    public let jobs: [FleetRunnerJob]
    public let nextCursor: String?

    public init(jobs: [FleetRunnerJob], nextCursor: String?) {
        self.jobs = jobs
        self.nextCursor = nextCursor
    }
}
