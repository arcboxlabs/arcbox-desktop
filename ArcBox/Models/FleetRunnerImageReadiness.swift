/// macOS runner image readiness presented on the runner page.
enum FleetRunnerImageReadiness: Equatable {
    case hidden
    case pending(reference: String)
    case preparing(FleetImagePreparationProgress)
    case restartRequired
    case completed(reference: String)
    case failed(String)
}
