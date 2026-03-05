import SwiftUI

struct SystemSettingsView: View {
    @State private var memoryLimit: Double = 9
    @State private var cpuLimit: Double = 17 // 17 = "None" (beyond max)
    @State private var useAdminPrivileges = true
    @State private var switchContextAutomatically = true
    @State private var useRosetta = true
    @State private var pauseContainersWhileSleeping = true

    private let memoryRange: ClosedRange<Double> = 1...14
    private let cpuSteps: [String] = ["100%", ""] // display only

    var body: some View {
        Form {
            Section {
                Text("Resources are only used as needed. These are limits, not reservations. [Learn more](#)")
                    .font(.callout)
                    .foregroundStyle(.secondary)

                LabeledContent {
                    HStack {
                        Text("1 GiB")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $memoryLimit, in: memoryRange, step: 1)
                        Text("14 GiB")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Memory limit")
                        Text("\(Int(memoryLimit)) GiB")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent {
                    HStack {
                        Text("100%")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                        Slider(value: $cpuLimit, in: 1...17, step: 1)
                        Text("None")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("CPU limit")
                        Text(cpuLimitLabel)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                Text("Resources")
            }

            Section("Environment") {
                LabeledContent {
                    Toggle("", isOn: $useAdminPrivileges)
                        .labelsHidden()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use admin privileges for enhanced features")
                        Text("This can improve performance and compatibility. [Learn more](#)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                Toggle("Switch Docker & Kubernetes context automatically", isOn: $switchContextAutomatically)
            }

            Section {
                LabeledContent {
                    Toggle("", isOn: $useRosetta)
                        .labelsHidden()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Use Rosetta to run Intel code")
                        Text("Faster. Only disable if you get errors.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }

                LabeledContent {
                    Toggle("", isOn: $pauseContainersWhileSleeping)
                        .labelsHidden()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Pause containers while Mac is sleeping")
                        Text("Improves battery life. Only disable if you need to run background services.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            } header: {
                VStack(alignment: .leading, spacing: 2) {
                    Text("Compatibility")
                    Text("Don't change these unless you run into issues.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
            }

            Section {
                HStack {
                    Spacer()
                    Button("Apply and Restart") {}
                        .disabled(true)
                    Spacer()
                }
            }
            .listRowBackground(Color.clear)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    private var cpuLimitLabel: String {
        if cpuLimit >= 17 {
            return "None"
        }
        return "\(Int(cpuLimit * 100 / 16))%"
    }
}

#Preview {
    SystemSettingsView()
        .frame(width: 500, height: 600)
}
