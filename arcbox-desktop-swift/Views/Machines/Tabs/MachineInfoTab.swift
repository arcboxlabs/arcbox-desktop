import SwiftUI

/// Info tab content showing machine details (content from screenshot reference)
struct MachineInfoTab: View {
    let machine: MachineViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Basic info section
                VStack(spacing: 0) {
                    InfoRow(label: "Name", value: machine.name)
                    InfoRow(label: "Status", value: machine.state.label)
                    if let ip = machine.ipAddress {
                        InfoRow(label: "IP", value: ip)
                    }
                }

                // Image section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Image")
                        .font(.system(size: 13, weight: .semibold))

                    VStack(spacing: 0) {
                        InfoRow(label: "Distro", value: machine.distro.displayName)
                        InfoRow(label: "Version", value: machine.distro.version)
                        InfoRow(label: "Architecture", value: "arm64")
                    }
                }

                // Resources section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Resources")
                        .font(.system(size: 13, weight: .semibold))

                    VStack(spacing: 0) {
                        InfoRow(label: "CPU", value: "\(machine.cpuCores) cores")
                        InfoRow(label: "Memory", value: "\(machine.memoryGB) GB")
                        InfoRow(label: "Disk", value: "\(machine.diskGB) GB")
                    }
                }
            }
            .padding(16)
        }
    }
}
