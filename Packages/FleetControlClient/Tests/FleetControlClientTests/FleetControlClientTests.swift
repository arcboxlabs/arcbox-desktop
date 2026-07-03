import Testing

@testable import FleetControlClient

@Test func generatedTypesAreAvailable() {
    let request = Arcbox_Fleet_Control_V1_GetAgentInfoRequest()
    #expect(request == Arcbox_Fleet_Control_V1_GetAgentInfoRequest())
}

@Test func settingsUpdatePreservesOptionalPresence() {
    let update = FleetSettingsUpdate(
        loadCeiling: 0,
        runnerImage: "",
        dockerMode: .disabled
    )

    let request = update.protoValue

    #expect(request.hasLoadCeiling)
    #expect(request.loadCeiling == 0)
    #expect(!request.hasMemFloorMib)
    #expect(request.hasRunnerImage)
    #expect(request.runnerImage == "")
    #expect(!request.hasGateway)
    #expect(request.hasDockerMode)
    #expect(request.dockerMode == .disabled)
    #expect(!request.hasRunnerScript)
}

@Test func settingsMappingPreservesCurrentTargetAndPresence() {
    var proto = Arcbox_Fleet_Control_V1_AgentSettings()

    var load = Arcbox_Fleet_Control_V1_DoubleSetting()
    load.current = 0.7
    load.target = 0.9
    proto.loadCeiling = load

    var dockerMode = Arcbox_Fleet_Control_V1_DockerModeSetting()
    dockerMode.current = .auto
    dockerMode.target = .disabled
    proto.dockerMode = dockerMode

    let settings = FleetAgentSettings(proto: proto)

    #expect(settings.loadCeiling == FleetSetting(current: 0.7, target: 0.9))
    #expect(settings.memFloorMib == nil)
    #expect(settings.runnerImage == nil)
    #expect(settings.dockerMode == FleetSetting(current: .auto, target: .disabled))
    #expect(settings.hasPendingChanges)
}

@Test func snapshotMappingPreservesOptionalTelemetryAndSettings() {
    var proto = Arcbox_Fleet_Control_V1_AgentStateSnapshot()
    proto.enrollment = .attached
    proto.draining = true

    var capability = Arcbox_Fleet_Control_V1_Capability()
    capability.os = "macos"
    capability.arch = "arm64"
    capability.backedBy = .vm
    proto.capabilities = [capability]

    var inFlight = Arcbox_Fleet_Control_V1_InFlightJob()
    inFlight.jobID = "job_123"
    inFlight.os = "macos"
    inFlight.arch = "arm64"
    proto.inFlight = [inFlight]

    var verdict = Arcbox_Fleet_Control_V1_OfferVerdict()
    verdict.jobID = "job_456"
    verdict.accepted = false
    verdict.reason = "draining"
    proto.recentVerdicts = [verdict]

    var telemetry = Arcbox_Fleet_Control_V1_HostTelemetry()
    telemetry.loadAvg1M = 1.25
    telemetry.cpuCount = 10
    telemetry.memTotalMib = 32768
    telemetry.memAvailableMib = 8192
    proto.telemetry = telemetry

    let snapshot = FleetAgentSnapshot(proto: proto)

    #expect(snapshot.enrollment == .attached)
    #expect(snapshot.machineID == nil)
    #expect(snapshot.isDraining)
    #expect(snapshot.capabilities == [FleetCapability(os: "macos", arch: "arm64", backend: .vm)])
    #expect(snapshot.inFlightJobs == [FleetInFlightJob(jobID: "job_123", os: "macos", arch: "arm64")])
    #expect(snapshot.recentVerdicts == [
        FleetOfferVerdict(jobID: "job_456", accepted: false, reason: "draining")
    ])
    #expect(snapshot.telemetry == FleetHostTelemetry(
        loadAverage1Minute: 1.25,
        cpuCount: 10,
        memoryTotalMib: 32768,
        memoryAvailableMib: 8192
    ))
    #expect(snapshot.settings == nil)
}

@Test func unrecognizedEnumsRoundTripForWritableDockerMode() {
    let mode = FleetDockerMode(proto: .UNRECOGNIZED(42))
    let request = FleetSettingsUpdate(dockerMode: mode).protoValue

    #expect(mode == .unrecognized(42))
    #expect(request.hasDockerMode)
    #expect(request.dockerMode == .UNRECOGNIZED(42))
}
