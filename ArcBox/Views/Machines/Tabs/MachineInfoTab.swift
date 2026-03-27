import SwiftUI

/// Info tab content showing machine details (content from screenshot reference)
struct MachineInfoTab: View {
    let machine: MachineViewModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Basic info section
                VStack(spacing: 0) {
                    InfoRow(label: "Name", value: machine.name, rowIndex: 0)
                    InfoRow(label: "Status", value: machine.state.label, rowIndex: 1)
                    if let ip = machine.ipAddress {
                        InfoRow(label: "IP", value: ip, rowIndex: 2)
                    }
                }
                .infoSectionStyle()

                // Image section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Image")
                        .font(.system(size: 13, weight: .semibold))

                    VStack(spacing: 0) {
                        InfoRow(label: "Distro", value: machine.distro.displayName, rowIndex: 0)
                        InfoRow(label: "Version", value: machine.distro.version, rowIndex: 1)
                        InfoRow(label: "Architecture", value: machine.architecture, rowIndex: 2)
                    }
                    .infoSectionStyle()
                }

                // Resources section
                VStack(alignment: .leading, spacing: 8) {
                    Text("Resources")
                        .font(.system(size: 13, weight: .semibold))

                    VStack(spacing: 0) {
                        InfoRow(label: "CPU", value: "\(machine.cpuCores) cores", rowIndex: 0)
                        InfoRow(label: "Memory", value: "\(machine.memoryGB) GB", rowIndex: 1)
                        InfoRow(label: "Disk", value: "\(machine.diskGB) GB", rowIndex: 2)
                    }
                    .infoSectionStyle()
                }
            }
            .padding(16)
        }
    }
}
