/// Explicit UI state for the Fleet Agent connection and enrollment lifecycle.
enum RunnersViewState: Equatable {
    case connecting
    case unavailable(String)
    case unenrolled
    case enrolled(RunnerHostViewModel)
}
