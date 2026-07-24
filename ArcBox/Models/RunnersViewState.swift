/// Explicit UI state for the Fleet Agent connection and enrollment lifecycle.
enum RunnersViewState: Equatable {
    case connecting
    case unavailable(String)
    case signedOut
    case unenrolled
    case enrolling(RunnerEnrollmentProgress)
    case enrollmentFailed(String, recovery: RunnerEnrollmentRecovery)
    case failed(String)
    case enrolled(RunnerHostViewModel, freshness: RunnerHostFreshness)
}

enum RunnerEnrollmentRecovery: Equatable {
    case retry
    case waitForAgent
    case unenroll
}

enum RunnerHostFreshness: Equatable {
    case live
    case reconnecting(String)
}

/// User-facing progress derived from the enrollment coordinator.
enum RunnerEnrollmentProgress: Equatable {
    case checkingAgent
    case requestingToken
    case enrollingAgent
    case reconciling
    case attaching
    case synchronizing

    var title: String {
        switch self {
        case .checkingAgent:
            "Checking Fleet Agent"
        case .requestingToken:
            "Requesting enrollment token"
        case .enrollingAgent:
            "Enrolling this Mac"
        case .reconciling:
            "Confirming enrollment"
        case .attaching:
            "Connecting to Fleet"
        case .synchronizing:
            "Finishing setup"
        }
    }

    var message: String {
        switch self {
        case .checkingAgent:
            "Waiting for the local Fleet Agent endpoint."
        case .requestingToken:
            "ArcBox is requesting a short-lived token for the selected workspace."
        case .enrollingAgent:
            "ArcBox is handing the short-lived token to the local Fleet Agent."
        case .reconciling:
            "Waiting for the Fleet Agent to report the enrollment result."
        case .attaching:
            "The Fleet Agent is attaching this Mac to the workspace."
        case .synchronizing:
            "Enrollment succeeded. Waiting for the live Agent state."
        }
    }
}
