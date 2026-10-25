import Testing

@testable import RunnerAgentClient

@Test func settingsUpdatePreservesOptionalPresence() {
    let update = RunnerSettingsUpdate(
        loadCeiling: 0,
        linuxRunnerImage: "",
        dockerMode: .disabled,
        participate: false,
        macosRunnerImage: "tahoe-base",
        vmMode: .enabled
    )

    let request = update.protoValue

    #expect(request.hasLoadCeiling)
    #expect(request.loadCeiling == 0)
    #expect(!request.hasMemFloorMib)
    #expect(request.hasLinuxRunnerImage)
    #expect(request.linuxRunnerImage.isEmpty)
    #expect(!request.hasGateway)
    #expect(request.hasDockerMode)
    #expect(request.dockerMode == .disabled)
    #expect(!request.hasRunnerScript)
    #expect(request.hasParticipate)
    #expect(!request.participate)
    #expect(request.hasMacosRunnerImage)
    #expect(request.macosRunnerImage == "tahoe-base")
    #expect(request.hasVmMode)
    #expect(request.vmMode == .enabled)
    #expect(!update.isEmpty)
    #expect(RunnerSettingsUpdate().isEmpty)
}

@Test func settingsMappingPreservesCurrentTargetAndPresence() {
    var proto = Arcbox_Runner_Control_V1_AgentSettings()

    var load = Arcbox_Runner_Control_V1_DoubleSetting()
    load.current = 0.7
    load.target = 0.9
    proto.loadCeiling = load

    var dockerMode = Arcbox_Runner_Control_V1_DockerModeSetting()
    dockerMode.current = .auto
    dockerMode.target = .disabled
    proto.dockerMode = dockerMode

    var linuxRunnerImage = Arcbox_Runner_Control_V1_StringSetting()
    linuxRunnerImage.current = "arcbox/runner@sha256:current"
    linuxRunnerImage.target = "arcbox/runner:latest"
    proto.linuxRunnerImage = linuxRunnerImage

    var participate = Arcbox_Runner_Control_V1_BoolSetting()
    participate.current = false
    participate.target = true
    proto.participate = participate

    var macosRunnerImage = Arcbox_Runner_Control_V1_StringSetting()
    macosRunnerImage.current = "tahoe-base@2026.07.02"
    macosRunnerImage.target = "tahoe-base"
    proto.macosRunnerImage = macosRunnerImage

    var vmMode = Arcbox_Runner_Control_V1_VmModeSetting()
    vmMode.current = .disabled
    vmMode.target = .auto
    proto.vmMode = vmMode

    let settings = RunnerAgentSettings(proto: proto)

    #expect(settings.loadCeiling == RunnerSetting(current: 0.7, target: 0.9))
    #expect(settings.memFloorMib == nil)
    #expect(
        settings.linuxRunnerImage
            == RunnerSetting(
                current: "arcbox/runner@sha256:current",
                target: "arcbox/runner:latest"
            ))
    #expect(settings.dockerMode == RunnerSetting(current: .auto, target: .disabled))
    #expect(settings.participate == RunnerSetting(current: false, target: true))
    #expect(
        settings.macosRunnerImage
            == RunnerSetting(current: "tahoe-base@2026.07.02", target: "tahoe-base"))
    #expect(settings.vmMode == RunnerSetting(current: .disabled, target: .auto))
    #expect(settings.hasPendingChanges)
}

@Test func newSettingsFieldsContributeToPendingStateIndependently() {
    let imagePending = RunnerAgentSettings(
        macosRunnerImage: RunnerSetting(current: "tahoe-base@old", target: "tahoe-base")
    )
    let vmModePending = RunnerAgentSettings(
        vmMode: RunnerSetting(current: .disabled, target: .enabled)
    )

    #expect(imagePending.hasPendingChanges)
    #expect(vmModePending.hasPendingChanges)
}

@Test func newLifecycleStatesMapWithoutLosingMeaning() {
    #expect(RunnerConnectionState(proto: .detached) == .detached)
    #expect(RunnerConnectionState(proto: .credentialRejected) == .credentialRejected)
    #expect(RunnerEnrollmentState(proto: .detached) == .detached)
    #expect(RunnerEnrollmentState(proto: .credentialRejected) == .credentialRejected)
    #expect(RunnerEnrollmentState(proto: .updating) == .updating)
}

@Test func imagePreparationMappingPreservesProgressAndUnknownKinds() {
    var proto = Arcbox_Runner_Control_V1_PrepareResponse()
    proto.kind = .UNRECOGNIZED(42)
    proto.detail = "linux/arm64"
    proto.stage = "pulling"
    proto.fraction = 0.75

    let event = RunnerImagePreparationEvent(proto: proto)

    #expect(
        event
            == RunnerImagePreparationEvent(
                kind: .unrecognized(42),
                detail: "linux/arm64",
                stage: "pulling",
                fraction: 0.75
            ))
    #expect(event.kind.protoValue == .UNRECOGNIZED(42))
    #expect(RunnerImageKind(proto: .macosRunnerImage) == .macosRunnerImage)
    #expect(RunnerImageKind.macosRunnerImage.protoValue == .macosRunnerImage)
}

@Test func snapshotMappingPreservesOptionalTelemetryAndSettings() {
    var proto = Arcbox_Runner_Control_V1_AgentStateSnapshot()
    proto.enrollment = .attached
    proto.draining = true

    var capability = Arcbox_Runner_Control_V1_Capability()
    capability.os = "macos"
    capability.arch = "arm64"
    capability.backedBy = .vm
    proto.capabilities = [capability]

    var inFlight = Arcbox_Runner_Control_V1_InFlightJob()
    inFlight.jobID = "job_123"
    inFlight.os = "macos"
    inFlight.arch = "arm64"
    proto.inFlight = [inFlight]

    var verdict = Arcbox_Runner_Control_V1_OfferVerdict()
    verdict.jobID = "job_456"
    verdict.accepted = false
    verdict.reason = "draining"
    proto.recentVerdicts = [verdict]

    var telemetry = Arcbox_Runner_Control_V1_HostTelemetry()
    telemetry.loadAvg1M = 1.25
    telemetry.cpuCount = 10
    telemetry.memTotalMib = 32768
    telemetry.memAvailableMib = 8192
    proto.telemetry = telemetry

    let snapshot = RunnerAgentSnapshot(proto: proto)

    #expect(snapshot.enrollment == .attached)
    #expect(snapshot.hostID == nil)
    #expect(snapshot.isDraining)
    #expect(snapshot.capabilities == [RunnerCapability(os: "macos", arch: "arm64", backend: .vm)])
    #expect(snapshot.inFlightJobs == [RunnerInFlightJob(jobID: "job_123", os: "macos", arch: "arm64")])
    #expect(
        snapshot.recentVerdicts == [
            RunnerOfferVerdict(jobID: "job_456", accepted: false, reason: "draining")
        ])
    #expect(
        snapshot.telemetry
            == RunnerHostTelemetry(
                loadAverage1Minute: 1.25,
                cpuCount: 10,
                memoryTotalMib: 32768,
                memoryAvailableMib: 8192
            ))
    #expect(snapshot.settings == nil)
}

@Test func unrecognizedWritableModesRoundTripWithoutLosingValues() {
    let dockerMode = RunnerDockerMode(proto: .UNRECOGNIZED(42))
    let vmMode = RunnerVmMode(proto: .UNRECOGNIZED(43))
    let request = RunnerSettingsUpdate(dockerMode: dockerMode, vmMode: vmMode).protoValue

    #expect(dockerMode == .unrecognized(42))
    #expect(request.hasDockerMode)
    #expect(request.dockerMode == .UNRECOGNIZED(42))
    #expect(vmMode == .unrecognized(43))
    #expect(request.hasVmMode)
    #expect(request.vmMode == .UNRECOGNIZED(43))
}
