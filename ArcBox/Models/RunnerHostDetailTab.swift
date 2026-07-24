enum RunnerHostDetailTab: String, CaseIterable, Identifiable {
    case overview = "Overview"
    case capacity = "Capacity"
    case settings = "Settings"
    case identity = "Identity"

    var id: Self { self }
}
