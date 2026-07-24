enum RunnerJobDetailTab: String, CaseIterable, Identifiable {
    case logs = "Logs"
    case info = "Info"
    case runtime = "Runtime"

    var id: Self { self }
}
