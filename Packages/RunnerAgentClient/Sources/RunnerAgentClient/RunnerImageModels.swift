/// A runner image setting that the local agent can prepare.
public enum RunnerImageKind: Equatable, Sendable {
    case unspecified
    case linuxRunnerImage
    case macosRunnerImage
    case unrecognized(Int)
}

/// Progress from RunnerImageService.Prepare for one image preparation step.
public struct RunnerImagePreparationEvent: Equatable, Sendable {
    public var kind: RunnerImageKind
    public var detail: String
    public var stage: String
    public var fraction: Double

    public init(
        kind: RunnerImageKind,
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

extension RunnerImageKind {
    init(proto: Arcbox_Runner_Control_V1_ImageKind) {
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

    var protoValue: Arcbox_Runner_Control_V1_ImageKind {
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

extension RunnerImagePreparationEvent {
    init(proto: Arcbox_Runner_Control_V1_PrepareResponse) {
        self.init(
            kind: RunnerImageKind(proto: proto.kind),
            detail: proto.detail,
            stage: proto.stage,
            fraction: proto.fraction
        )
    }
}
