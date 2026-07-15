/// A fleet image setting that the local agent can prepare.
public enum FleetImageKind: Equatable, Sendable {
    case unspecified
    case linuxRunnerImage
    case macosRunnerImage
    case unrecognized(Int)
}

/// Progress from FleetImageService.Prepare for one image preparation step.
public struct FleetImagePreparationEvent: Equatable, Sendable {
    public var kind: FleetImageKind
    public var detail: String
    public var stage: String
    public var fraction: Double

    public init(
        kind: FleetImageKind,
        detail: String,
        stage: String,
        fraction: Double
    ) {
        self.kind = kind
        self.detail = detail
        self.stage = stage
        self.fraction = fraction
    }
}

extension FleetImageKind {
    init(proto: Arcbox_Fleet_Control_V1_ImageKind) {
        switch proto {
        case .unspecified:
            self = .unspecified
        case .linuxRunnerImage:
            self = .linuxRunnerImage
        case .macosRunnerImage:
            self = .macosRunnerImage
        case .UNRECOGNIZED(let value):
            self = .unrecognized(value)
        }
    }

    var protoValue: Arcbox_Fleet_Control_V1_ImageKind {
        switch self {
        case .unspecified:
            return .unspecified
        case .linuxRunnerImage:
            return .linuxRunnerImage
        case .macosRunnerImage:
            return .macosRunnerImage
        case .unrecognized(let value):
            return .UNRECOGNIZED(value)
        }
    }
}

extension FleetImagePreparationEvent {
    init(proto: Arcbox_Fleet_Control_V1_PrepareResponse) {
        self.init(
            kind: FleetImageKind(proto: proto.kind),
            detail: proto.detail,
            stage: proto.stage,
            fraction: proto.fraction
        )
    }
}
