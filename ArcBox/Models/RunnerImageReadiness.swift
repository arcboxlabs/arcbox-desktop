/// macOS runner image readiness presented on the runner page.
enum RunnerImageReadiness: Equatable {
    case hidden
    case pending(reference: String)
    case preparing(RunnerImagePreparationProgress)
    case restartRequired
    case completed(reference: String)
    case failed(String)
}
