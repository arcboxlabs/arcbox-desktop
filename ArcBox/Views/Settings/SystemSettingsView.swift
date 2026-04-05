import SwiftUI

struct SystemSettingsView: View {
    // TODO: Implement resource controls (CPU/Memory) and environment
    // toggles (Admin/Rosetta) when backend gRPC APIs are available (ABXD-87)
    // @State private var memoryLimit: Double = 9
    // @State private var cpuLimit: Double = 17 // 17 = "None" (beyond max)
    // @State private var useAdminPrivileges = true
    @AppStorage("switchDockerContextAutomatically") private var switchContextAutomatically = true
    // @State private var useRosetta = true
    @AppStorage("pauseContainersWhileSleeping") private var pauseContainersWhileSleeping = true

    // private let memoryRange: ClosedRange<Double> = 1...14

    var body: some View {
        Form {
            // TODO: Implement resource controls when backend gRPC APIs are available (ABXD-87)
            // Section {
            //     Text("Resources are only used as needed. These are limits, not reservations. [Learn more](#)")
            //         .font(.callout)
            //         .foregroundStyle(.secondary)
            //
            //     LabeledContent {
            //         HStack {
            //             Text("1 GiB")
            //                 .font(.caption)
            //                 .foregroundStyle(.secondary)
            //             Slider(value: $memoryLimit, in: memoryRange, step: 1)
            //             Text("14 GiB")
            //                 .font(.caption)
            //                 .foregroundStyle(.secondary)
            //         }
            //     } label: {
            //         VStack(alignment: .leading, spacing: 2) {
            //             Text("Memory limit")
            //             Text("\(Int(memoryLimit)) GiB")
            //                 .font(.caption)
            //                 .foregroundStyle(.secondary)
            //         }
            //     }
            //
            //     LabeledContent {
            //         HStack {
            //             Text("100%")
            //                 .font(.caption)
            //                 .foregroundStyle(.secondary)
            //             Slider(value: $cpuLimit, in: 1...17, step: 1)
            //             Text("None")
            //                 .font(.caption)
            //                 .foregroundStyle(.secondary)
            //         }
            //     } label: {
            //         VStack(alignment: .leading, spacing: 2) {
            //             Text("CPU limit")
            //             Text(cpuLimitLabel)
            //                 .font(.caption)
            //                 .foregroundStyle(.secondary)
            //         }
            //     }
            // } header: {
            //     Text("Resources")
            // }

            Section("Environment") {
                // TODO: Implement admin privileges toggle (ABXD-87)
                // LabeledContent {
                //     Toggle("", isOn: $useAdminPrivileges)
                //         .labelsHidden()
                // } label: {
                //     VStack(alignment: .leading, spacing: 2) {
                //         Text("Use admin privileges for enhanced features")
                //         Text("This can improve performance and compatibility. [Learn more](#)")
                //             .font(.caption)
                //             .foregroundStyle(.secondary)
                //     }
                // }

                // TODO: Implement Kubernetes context auto-switch (ABXD-86)
                Toggle("Switch Docker & Kubernetes context automatically", isOn: $switchContextAutomatically)
            }

            Section {
                // TODO: Implement Rosetta toggle (ABXD-87)
                // LabeledContent {
                //     Toggle("", isOn: $useRosetta)
                //         .labelsHidden()
                // } label: {
                //     VStack(alignment: .leading, spacing: 2) {
                //         Text("Use Rosetta to run Intel code")
                //         Text("Faster. Only disable if you get errors.")
                //             .font(.caption)
                //             .foregroundStyle(.secondary)
                //     }
                // }

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

            // TODO: Implement Apply and Restart (ABXD-87)
            // Section {
            //     HStack {
            //         Spacer()
            //         Button("Apply and Restart") {}
            //             .disabled(true)
            //         Spacer()
            //     }
            // }
            // .listRowBackground(Color.clear)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }

    // TODO: Uncomment when CPU limit slider is enabled (ABXD-87)
    // private var cpuLimitLabel: String {
    //     if cpuLimit >= 17 {
    //         return "None"
    //     }
    //     return "\(Int(cpuLimit * 100 / 16))%"
    // }
}

#Preview {
    SystemSettingsView()
        .frame(width: 500, height: 600)
}
