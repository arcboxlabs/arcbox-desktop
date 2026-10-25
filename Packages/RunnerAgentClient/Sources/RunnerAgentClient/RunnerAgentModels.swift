/// Version and capability handshake returned by the local runner agent.
public struct RunnerAgentInfo: Equatable, Sendable {
    public var agentVersion: String
    public var apiVersion: UInt32
    public var features: [String]

    public init(agentVersion: String, apiVersion: UInt32, features: [String]) {
        self.agentVersion = agentVersion
        self.apiVersion = apiVersion
        self.features = features
    }

    public func supportsFeature(_ feature: String) -> Bool {
        features.contains(feature)
    }
}

/// Coarse lifecycle status from RunnerLifecycleService.GetStatus.
public struct RunnerAgentStatus: Equatable, Sendable {
    public var state: RunnerConnectionState
    public var hostID: String?

    public init(state: RunnerConnectionState, hostID: String?) {
        self.state = state
        self.hostID = hostID
    }
}

/// Coarse enrollment state exposed by GetStatus.
public enum RunnerConnectionState: Equatable, Sendable {
    case unspecified
    case unenrolled
    case enrolled
    case draining
    case detached
    case credentialRejected
    case unrecognized(Int)
}

/// Live enrollment/connectivity state exposed by Watch snapshots.
public enum RunnerEnrollmentState: Equatable, Sendable {
    case unspecified
    case unenrolled
    case attaching
    case attached
    case updating
    case detached
    case credentialRejected
    case unrecognized(Int)
}

/// Execution backend advertised for a runner host capability.
public enum RunnerBackend: Equatable, Sendable {
    case unspecified
    case hostRunner
    case docker
    case vm
    case unrecognized(Int)
}

/// Docker runner policy mode.
public enum RunnerDockerMode: Equatable, Sendable {
    case unspecified
    case auto
    case enabled
    case disabled
    case unrecognized(Int)
}

/// macOS runner VM policy mode.
public enum RunnerVmMode: Equatable, Sendable {
    case unspecified
    case auto
    case enabled
    case disabled
    case unrecognized(Int)
}

/// A setting with an observed current value and a desired target value.
public struct RunnerSetting<Value: Equatable & Sendable>: Equatable, Sendable {
    public var current: Value
    public var target: Value

    public init(current: Value, target: Value) {
        self.current = current
        self.target = target
    }

    public var isPending: Bool {
        current != target
    }
}

/// Persisted runner agent settings, preserving field presence from the proto.
public struct RunnerAgentSettings: Equatable, Sendable {
    public var loadCeiling: RunnerSetting<Double>?
    public var memFloorMib: RunnerSetting<UInt64>?
    public var linuxRunnerImage: RunnerSetting<String>?
    public var gateway: RunnerSetting<String>?
    public var dockerMode: RunnerSetting<RunnerDockerMode>?
    public var runnerScript: RunnerSetting<String>?
    public var participate: RunnerSetting<Bool>?
    public var macosRunnerImage: RunnerSetting<String>?
    public var vmMode: RunnerSetting<RunnerVmMode>?

    public init(
        loadCeiling: RunnerSetting<Double>? = nil,
        memFloorMib: RunnerSetting<UInt64>? = nil,
        linuxRunnerImage: RunnerSetting<String>? = nil,
        gateway: RunnerSetting<String>? = nil,
        dockerMode: RunnerSetting<RunnerDockerMode>? = nil,
        runnerScript: RunnerSetting<String>? = nil,
        participate: RunnerSetting<Bool>? = nil,
        macosRunnerImage: RunnerSetting<String>? = nil,
        vmMode: RunnerSetting<RunnerVmMode>? = nil
    ) {
        self.loadCeiling = loadCeiling
        self.memFloorMib = memFloorMib
        self.linuxRunnerImage = linuxRunnerImage
        self.gateway = gateway
        self.dockerMode = dockerMode
        self.runnerScript = runnerScript
        self.participate = participate
        self.macosRunnerImage = macosRunnerImage
        self.vmMode = vmMode
    }

    public var hasPendingChanges: Bool {
        loadCeiling?.isPending == true
            || memFloorMib?.isPending == true
            || linuxRunnerImage?.isPending == true
            || gateway?.isPending == true
            || dockerMode?.isPending == true
            || runnerScript?.isPending == true
            || participate?.isPending == true
            || macosRunnerImage?.isPending == true
            || vmMode?.isPending == true
    }
}

/// Partial settings update. Nil means "leave this field unchanged".
public struct RunnerSettingsUpdate: Equatable, Sendable {
    public var loadCeiling: Double?
    public var memFloorMib: UInt64?
    public var linuxRunnerImage: String?
    public var gateway: String?
    public var dockerMode: RunnerDockerMode?
    public var runnerScript: String?
    public var participate: Bool?
    public var macosRunnerImage: String?
    public var vmMode: RunnerVmMode?

    public init(
        loadCeiling: Double? = nil,
        memFloorMib: UInt64? = nil,
        linuxRunnerImage: String? = nil,
        gateway: String? = nil,
        dockerMode: RunnerDockerMode? = nil,
        runnerScript: String? = nil,
        participate: Bool? = nil,
        macosRunnerImage: String? = nil,
        vmMode: RunnerVmMode? = nil
    ) {
        self.loadCeiling = loadCeiling
        self.memFloorMib = memFloorMib
        self.linuxRunnerImage = linuxRunnerImage
        self.gateway = gateway
        self.dockerMode = dockerMode
        self.runnerScript = runnerScript
        self.participate = participate
        self.macosRunnerImage = macosRunnerImage
        self.vmMode = vmMode
    }

    public var isEmpty: Bool {
        loadCeiling == nil
            && memFloorMib == nil
            && linuxRunnerImage == nil
            && gateway == nil
            && dockerMode == nil
            && runnerScript == nil
            && participate == nil
            && macosRunnerImage == nil
            && vmMode == nil
    }
}

/// Host telemetry reported by the runner agent.
public struct RunnerHostTelemetry: Equatable, Sendable {
    public var loadAverage1Minute: Double
    public var cpuCount: UInt32
    public var memoryTotalMib: UInt64
    public var memoryAvailableMib: UInt64

    public init(
        loadAverage1Minute: Double,
        cpuCount: UInt32,
        memoryTotalMib: UInt64,
        memoryAvailableMib: UInt64
    ) {
        self.loadAverage1Minute = loadAverage1Minute
        self.cpuCount = cpuCount
        self.memoryTotalMib = memoryTotalMib
        self.memoryAvailableMib = memoryAvailableMib
    }
}

/// Capability advertised by this host.
public struct RunnerCapability: Equatable, Sendable, Identifiable {
    public var os: String
    public var arch: String
    public var backend: RunnerBackend

    public init(os: String, arch: String, backend: RunnerBackend) {
        self.os = os
        self.arch = arch
        self.backend = backend
    }

    public var id: String {
        "\(os):\(arch):\(backend)"
    }
}

/// Job currently running on this host.
public struct RunnerInFlightJob: Equatable, Sendable, Identifiable {
    public var jobID: String
    public var os: String
    public var arch: String

    public init(jobID: String, os: String, arch: String) {
        self.jobID = jobID
        self.os = os
        self.arch = arch
    }

    public var id: String {
        jobID
    }
}

/// Recent offer admission decision reported by the agent.
public struct RunnerOfferVerdict: Equatable, Sendable, Identifiable {
    public var jobID: String
    public var accepted: Bool
    public var reason: String?

    public init(jobID: String, accepted: Bool, reason: String?) {
        self.jobID = jobID
        self.accepted = accepted
        self.reason = reason
    }

    public var id: String {
        "\(jobID):\(accepted):\(reason ?? "")"
    }
}

/// Full live state snapshot streamed by RunnerStateService.Watch.
public struct RunnerAgentSnapshot: Equatable, Sendable {
    public var enrollment: RunnerEnrollmentState
    public var hostID: String?
    public var isDraining: Bool
    public var capabilities: [RunnerCapability]
    public var inFlightJobs: [RunnerInFlightJob]
    public var recentVerdicts: [RunnerOfferVerdict]
    public var telemetry: RunnerHostTelemetry?
    public var settings: RunnerAgentSettings?

    public init(
        enrollment: RunnerEnrollmentState,
        hostID: String?,
        isDraining: Bool,
        capabilities: [RunnerCapability],
        inFlightJobs: [RunnerInFlightJob],
        recentVerdicts: [RunnerOfferVerdict],
        telemetry: RunnerHostTelemetry?,
        settings: RunnerAgentSettings?
    ) {
        self.enrollment = enrollment
        self.hostID = hostID
        self.isDraining = isDraining
        self.capabilities = capabilities
        self.inFlightJobs = inFlightJobs
        self.recentVerdicts = recentVerdicts
        self.telemetry = telemetry
        self.settings = settings
    }
}

extension RunnerAgentInfo {
    init(proto: Arcbox_Runner_Control_V1_GetAgentInfoResponse) {
        self.init(
            agentVersion: proto.agentVersion,
            apiVersion: proto.apiVersion,
            features: proto.features
        )
    }
}

extension RunnerAgentStatus {
    init(proto: Arcbox_Runner_Control_V1_GetStatusResponse) {
        self.init(
            state: RunnerConnectionState(proto: proto.state),
            hostID: proto.hostID.nonEmpty
        )
    }
}

extension RunnerConnectionState {
    init(proto: Arcbox_Runner_Control_V1_ConnectionState) {
        switch proto {
        case .unspecified:
            self = .unspecified
        case .unenrolled:
            self = .unenrolled
        case .enrolled:
            self = .enrolled
        case .draining:
            self = .draining
        case .detached:
            self = .detached
        case .credentialRejected:
            self = .credentialRejected
        case .UNRECOGNIZED(let value):
            self = .unrecognized(value)
        }
    }
}

extension RunnerEnrollmentState {
    init(proto: Arcbox_Runner_Control_V1_Enrollment) {
        switch proto {
        case .unspecified:
            self = .unspecified
        case .unenrolled:
            self = .unenrolled
        case .attaching:
            self = .attaching
        case .attached:
            self = .attached
        case .updating:
            self = .updating
        case .detached:
            self = .detached
        case .credentialRejected:
            self = .credentialRejected
        case .UNRECOGNIZED(let value):
            self = .unrecognized(value)
        }
    }
}

extension RunnerBackend {
    init(proto: Arcbox_Runner_Control_V1_Backend) {
        switch proto {
        case .unspecified:
            self = .unspecified
        case .hostRunner:
            self = .hostRunner
        case .docker:
            self = .docker
        case .vm:
            self = .vm
        case .UNRECOGNIZED(let value):
            self = .unrecognized(value)
        }
    }
}

extension RunnerDockerMode {
    init(proto: Arcbox_Runner_Control_V1_DockerMode) {
        switch proto {
        case .unspecified:
            self = .unspecified
        case .auto:
            self = .auto
        case .enabled:
            self = .enabled
        case .disabled:
            self = .disabled
        case .UNRECOGNIZED(let value):
            self = .unrecognized(value)
        }
    }

    var protoValue: Arcbox_Runner_Control_V1_DockerMode {
        switch self {
        case .unspecified:
            return .unspecified
        case .auto:
            return .auto
        case .enabled:
            return .enabled
        case .disabled:
            return .disabled
        case .unrecognized(let value):
            return .UNRECOGNIZED(value)
        }
    }
}

extension RunnerVmMode {
    init(proto: Arcbox_Runner_Control_V1_VmMode) {
        switch proto {
        case .unspecified:
            self = .unspecified
        case .auto:
            self = .auto
        case .enabled:
            self = .enabled
        case .disabled:
            self = .disabled
        case .UNRECOGNIZED(let value):
            self = .unrecognized(value)
        }
    }

    var protoValue: Arcbox_Runner_Control_V1_VmMode {
        switch self {
        case .unspecified:
            return .unspecified
        case .auto:
            return .auto
        case .enabled:
            return .enabled
        case .disabled:
            return .disabled
        case .unrecognized(let value):
            return .UNRECOGNIZED(value)
        }
    }
}

extension RunnerAgentSettings {
    init(proto: Arcbox_Runner_Control_V1_AgentSettings) {
        self.init(
            loadCeiling: proto.hasLoadCeiling
                ? RunnerSetting(current: proto.loadCeiling.current, target: proto.loadCeiling.target)
                : nil,
            memFloorMib: proto.hasMemFloorMib
                ? RunnerSetting(current: proto.memFloorMib.current, target: proto.memFloorMib.target)
                : nil,
            linuxRunnerImage: proto.hasLinuxRunnerImage
                ? RunnerSetting(
                    current: proto.linuxRunnerImage.current,
                    target: proto.linuxRunnerImage.target
                )
                : nil,
            gateway: proto.hasGateway
                ? RunnerSetting(current: proto.gateway.current, target: proto.gateway.target)
                : nil,
            dockerMode: proto.hasDockerMode
                ? RunnerSetting(
                    current: RunnerDockerMode(proto: proto.dockerMode.current),
                    target: RunnerDockerMode(proto: proto.dockerMode.target)
                )
                : nil,
            runnerScript: proto.hasRunnerScript
                ? RunnerSetting(current: proto.runnerScript.current, target: proto.runnerScript.target)
                : nil,
            participate: proto.hasParticipate
                ? RunnerSetting(current: proto.participate.current, target: proto.participate.target)
                : nil,
            macosRunnerImage: proto.hasMacosRunnerImage
                ? RunnerSetting(
                    current: proto.macosRunnerImage.current,
                    target: proto.macosRunnerImage.target
                )
                : nil,
            vmMode: proto.hasVmMode
                ? RunnerSetting(
                    current: RunnerVmMode(proto: proto.vmMode.current),
                    target: RunnerVmMode(proto: proto.vmMode.target)
                )
                : nil
        )
    }
}

extension RunnerSettingsUpdate {
    var protoValue: Arcbox_Runner_Control_V1_UpdateSettingsRequest {
        var request = Arcbox_Runner_Control_V1_UpdateSettingsRequest()
        if let loadCeiling {
            request.loadCeiling = loadCeiling
        }
        if let memFloorMib {
            request.memFloorMib = memFloorMib
        }
        if let linuxRunnerImage {
            request.linuxRunnerImage = linuxRunnerImage
        }
        if let gateway {
            request.gateway = gateway
        }
        if let dockerMode {
            request.dockerMode = dockerMode.protoValue
        }
        if let runnerScript {
            request.runnerScript = runnerScript
        }
        if let participate {
            request.participate = participate
        }
        if let macosRunnerImage {
            request.macosRunnerImage = macosRunnerImage
        }
        if let vmMode {
            request.vmMode = vmMode.protoValue
        }
        return request
    }
}

extension RunnerHostTelemetry {
    init(proto: Arcbox_Runner_Control_V1_HostTelemetry) {
        self.init(
            loadAverage1Minute: proto.loadAvg1M,
            cpuCount: proto.cpuCount,
            memoryTotalMib: proto.memTotalMib,
            memoryAvailableMib: proto.memAvailableMib
        )
    }
}

extension RunnerCapability {
    init(proto: Arcbox_Runner_Control_V1_Capability) {
        self.init(
            os: proto.os,
            arch: proto.arch,
            backend: RunnerBackend(proto: proto.backedBy)
        )
    }
}

extension RunnerInFlightJob {
    init(proto: Arcbox_Runner_Control_V1_InFlightJob) {
        self.init(
            jobID: proto.jobID,
            os: proto.os,
            arch: proto.arch
        )
    }
}

extension RunnerOfferVerdict {
    init(proto: Arcbox_Runner_Control_V1_OfferVerdict) {
        self.init(
            jobID: proto.jobID,
            accepted: proto.accepted,
            reason: proto.reason.nonEmpty
        )
    }
}

extension RunnerAgentSnapshot {
    init(proto: Arcbox_Runner_Control_V1_AgentStateSnapshot) {
        self.init(
            enrollment: RunnerEnrollmentState(proto: proto.enrollment),
            hostID: proto.hostID.nonEmpty,
            isDraining: proto.draining,
            capabilities: proto.capabilities.map(RunnerCapability.init(proto:)),
            inFlightJobs: proto.inFlight.map(RunnerInFlightJob.init(proto:)),
            recentVerdicts: proto.recentVerdicts.map(RunnerOfferVerdict.init(proto:)),
            telemetry: proto.hasTelemetry ? RunnerHostTelemetry(proto: proto.telemetry) : nil,
            settings: proto.hasSettings ? RunnerAgentSettings(proto: proto.settings) : nil
        )
    }

    init?(proto: Arcbox_Runner_Control_V1_WatchResponse) {
        guard proto.hasSnapshot else { return nil }
        self.init(proto: proto.snapshot)
    }
}

extension String {
    fileprivate var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
