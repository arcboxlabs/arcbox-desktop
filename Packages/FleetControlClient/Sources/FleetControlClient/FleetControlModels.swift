/// Version and capability handshake returned by the local fleet agent.
public struct FleetAgentInfo: Equatable, Sendable {
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

/// Coarse lifecycle status from FleetLifecycleService.GetStatus.
public struct FleetAgentStatus: Equatable, Sendable {
    public var state: FleetConnectionState
    public var machineID: String?

    public init(state: FleetConnectionState, machineID: String?) {
        self.state = state
        self.machineID = machineID
    }
}

/// Coarse enrollment state exposed by GetStatus.
public enum FleetConnectionState: Equatable, Sendable {
    case unspecified
    case unenrolled
    case enrolled
    case draining
    case detached
    case credentialRejected
    case unrecognized(Int)
}

/// Live enrollment/connectivity state exposed by Watch snapshots.
public enum FleetEnrollmentState: Equatable, Sendable {
    case unspecified
    case unenrolled
    case attaching
    case attached
    case detached
    case credentialRejected
    case unrecognized(Int)
}

/// Execution backend advertised for a fleet capability.
public enum FleetBackend: Equatable, Sendable {
    case unspecified
    case hostRunner
    case docker
    case vm
    case unrecognized(Int)
}

/// Docker runner policy mode.
public enum FleetDockerMode: Equatable, Sendable {
    case unspecified
    case auto
    case enabled
    case disabled
    case unrecognized(Int)
}

/// macOS runner VM policy mode.
public enum FleetVmMode: Equatable, Sendable {
    case unspecified
    case auto
    case enabled
    case disabled
    case unrecognized(Int)
}

/// A setting with an observed current value and a desired target value.
public struct FleetSetting<Value: Equatable & Sendable>: Equatable, Sendable {
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

/// Persisted fleet-agent settings, preserving field presence from the proto.
public struct FleetAgentSettings: Equatable, Sendable {
    public var loadCeiling: FleetSetting<Double>?
    public var memFloorMib: FleetSetting<UInt64>?
    public var linuxRunnerImage: FleetSetting<String>?
    public var gateway: FleetSetting<String>?
    public var dockerMode: FleetSetting<FleetDockerMode>?
    public var runnerScript: FleetSetting<String>?
    public var participate: FleetSetting<Bool>?
    public var macosRunnerImage: FleetSetting<String>?
    public var vmMode: FleetSetting<FleetVmMode>?

    public init(
        loadCeiling: FleetSetting<Double>? = nil,
        memFloorMib: FleetSetting<UInt64>? = nil,
        linuxRunnerImage: FleetSetting<String>? = nil,
        gateway: FleetSetting<String>? = nil,
        dockerMode: FleetSetting<FleetDockerMode>? = nil,
        runnerScript: FleetSetting<String>? = nil,
        participate: FleetSetting<Bool>? = nil,
        macosRunnerImage: FleetSetting<String>? = nil,
        vmMode: FleetSetting<FleetVmMode>? = nil
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
public struct FleetSettingsUpdate: Equatable, Sendable {
    public var loadCeiling: Double?
    public var memFloorMib: UInt64?
    public var linuxRunnerImage: String?
    public var gateway: String?
    public var dockerMode: FleetDockerMode?
    public var runnerScript: String?
    public var participate: Bool?
    public var macosRunnerImage: String?
    public var vmMode: FleetVmMode?

    public init(
        loadCeiling: Double? = nil,
        memFloorMib: UInt64? = nil,
        linuxRunnerImage: String? = nil,
        gateway: String? = nil,
        dockerMode: FleetDockerMode? = nil,
        runnerScript: String? = nil,
        participate: Bool? = nil,
        macosRunnerImage: String? = nil,
        vmMode: FleetVmMode? = nil
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

/// Host telemetry reported by the fleet agent.
public struct FleetHostTelemetry: Equatable, Sendable {
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
public struct FleetCapability: Equatable, Sendable, Identifiable {
    public var os: String
    public var arch: String
    public var backend: FleetBackend

    public init(os: String, arch: String, backend: FleetBackend) {
        self.os = os
        self.arch = arch
        self.backend = backend
    }

    public var id: String {
        "\(os):\(arch):\(backend)"
    }
}

/// Job currently running on this host.
public struct FleetInFlightJob: Equatable, Sendable, Identifiable {
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
public struct FleetOfferVerdict: Equatable, Sendable, Identifiable {
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

/// Full live state snapshot streamed by FleetStateService.Watch.
public struct FleetAgentSnapshot: Equatable, Sendable {
    public var enrollment: FleetEnrollmentState
    public var machineID: String?
    public var isDraining: Bool
    public var capabilities: [FleetCapability]
    public var inFlightJobs: [FleetInFlightJob]
    public var recentVerdicts: [FleetOfferVerdict]
    public var telemetry: FleetHostTelemetry?
    public var settings: FleetAgentSettings?

    public init(
        enrollment: FleetEnrollmentState,
        machineID: String?,
        isDraining: Bool,
        capabilities: [FleetCapability],
        inFlightJobs: [FleetInFlightJob],
        recentVerdicts: [FleetOfferVerdict],
        telemetry: FleetHostTelemetry?,
        settings: FleetAgentSettings?
    ) {
        self.enrollment = enrollment
        self.machineID = machineID
        self.isDraining = isDraining
        self.capabilities = capabilities
        self.inFlightJobs = inFlightJobs
        self.recentVerdicts = recentVerdicts
        self.telemetry = telemetry
        self.settings = settings
    }
}

extension FleetAgentInfo {
    init(proto: Arcbox_Fleet_Control_V1_GetAgentInfoResponse) {
        self.init(
            agentVersion: proto.agentVersion,
            apiVersion: proto.apiVersion,
            features: proto.features
        )
    }
}

extension FleetAgentStatus {
    init(proto: Arcbox_Fleet_Control_V1_GetStatusResponse) {
        self.init(
            state: FleetConnectionState(proto: proto.state),
            machineID: proto.machineID.nonEmpty
        )
    }
}

extension FleetConnectionState {
    init(proto: Arcbox_Fleet_Control_V1_ConnectionState) {
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

extension FleetEnrollmentState {
    init(proto: Arcbox_Fleet_Control_V1_Enrollment) {
        switch proto {
        case .unspecified:
            self = .unspecified
        case .unenrolled:
            self = .unenrolled
        case .attaching:
            self = .attaching
        case .attached:
            self = .attached
        case .detached:
            self = .detached
        case .credentialRejected:
            self = .credentialRejected
        case .UNRECOGNIZED(let value):
            self = .unrecognized(value)
        }
    }
}

extension FleetBackend {
    init(proto: Arcbox_Fleet_Control_V1_Backend) {
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

extension FleetDockerMode {
    init(proto: Arcbox_Fleet_Control_V1_DockerMode) {
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

    var protoValue: Arcbox_Fleet_Control_V1_DockerMode {
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

extension FleetVmMode {
    init(proto: Arcbox_Fleet_Control_V1_VmMode) {
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

    var protoValue: Arcbox_Fleet_Control_V1_VmMode {
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

extension FleetAgentSettings {
    init(proto: Arcbox_Fleet_Control_V1_AgentSettings) {
        self.init(
            loadCeiling: proto.hasLoadCeiling
                ? FleetSetting(current: proto.loadCeiling.current, target: proto.loadCeiling.target)
                : nil,
            memFloorMib: proto.hasMemFloorMib
                ? FleetSetting(current: proto.memFloorMib.current, target: proto.memFloorMib.target)
                : nil,
            linuxRunnerImage: proto.hasLinuxRunnerImage
                ? FleetSetting(
                    current: proto.linuxRunnerImage.current,
                    target: proto.linuxRunnerImage.target
                )
                : nil,
            gateway: proto.hasGateway
                ? FleetSetting(current: proto.gateway.current, target: proto.gateway.target)
                : nil,
            dockerMode: proto.hasDockerMode
                ? FleetSetting(
                    current: FleetDockerMode(proto: proto.dockerMode.current),
                    target: FleetDockerMode(proto: proto.dockerMode.target)
                )
                : nil,
            runnerScript: proto.hasRunnerScript
                ? FleetSetting(current: proto.runnerScript.current, target: proto.runnerScript.target)
                : nil,
            participate: proto.hasParticipate
                ? FleetSetting(current: proto.participate.current, target: proto.participate.target)
                : nil,
            macosRunnerImage: proto.hasMacosRunnerImage
                ? FleetSetting(
                    current: proto.macosRunnerImage.current,
                    target: proto.macosRunnerImage.target
                )
                : nil,
            vmMode: proto.hasVmMode
                ? FleetSetting(
                    current: FleetVmMode(proto: proto.vmMode.current),
                    target: FleetVmMode(proto: proto.vmMode.target)
                )
                : nil
        )
    }
}

extension FleetSettingsUpdate {
    var protoValue: Arcbox_Fleet_Control_V1_UpdateSettingsRequest {
        var request = Arcbox_Fleet_Control_V1_UpdateSettingsRequest()
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

extension FleetHostTelemetry {
    init(proto: Arcbox_Fleet_Control_V1_HostTelemetry) {
        self.init(
            loadAverage1Minute: proto.loadAvg1M,
            cpuCount: proto.cpuCount,
            memoryTotalMib: proto.memTotalMib,
            memoryAvailableMib: proto.memAvailableMib
        )
    }
}

extension FleetCapability {
    init(proto: Arcbox_Fleet_Control_V1_Capability) {
        self.init(
            os: proto.os,
            arch: proto.arch,
            backend: FleetBackend(proto: proto.backedBy)
        )
    }
}

extension FleetInFlightJob {
    init(proto: Arcbox_Fleet_Control_V1_InFlightJob) {
        self.init(
            jobID: proto.jobID,
            os: proto.os,
            arch: proto.arch
        )
    }
}

extension FleetOfferVerdict {
    init(proto: Arcbox_Fleet_Control_V1_OfferVerdict) {
        self.init(
            jobID: proto.jobID,
            accepted: proto.accepted,
            reason: proto.reason.nonEmpty
        )
    }
}

extension FleetAgentSnapshot {
    init(proto: Arcbox_Fleet_Control_V1_AgentStateSnapshot) {
        self.init(
            enrollment: FleetEnrollmentState(proto: proto.enrollment),
            machineID: proto.machineID.nonEmpty,
            isDraining: proto.draining,
            capabilities: proto.capabilities.map(FleetCapability.init(proto:)),
            inFlightJobs: proto.inFlight.map(FleetInFlightJob.init(proto:)),
            recentVerdicts: proto.recentVerdicts.map(FleetOfferVerdict.init(proto:)),
            telemetry: proto.hasTelemetry ? FleetHostTelemetry(proto: proto.telemetry) : nil,
            settings: proto.hasSettings ? FleetAgentSettings(proto: proto.settings) : nil
        )
    }

    init?(proto: Arcbox_Fleet_Control_V1_WatchResponse) {
        guard proto.hasSnapshot else { return nil }
        self.init(proto: proto.snapshot)
    }
}

extension String {
    fileprivate var nonEmpty: String? {
        isEmpty ? nil : self
    }
}
