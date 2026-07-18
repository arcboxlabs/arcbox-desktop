import SwiftUI

/// Info tab content showing machine details.
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
                    InfoRow(label: "Created", value: machine.createdAt.formatted())
                    if let startedAt = machine.startedAt {
                        InfoRow(label: "Started", value: startedAt.formatted())
                    }
                }
                .infoSectionStyle()

                // Image section
                section("Image") {
                    InfoRow(label: "Distro", value: machine.distro.displayName)
                    InfoRow(label: "Version", value: machine.distro.version)
                    if !machine.architecture.isEmpty {
                        InfoRow(label: "Architecture", value: machine.architecture)
                    }
                }

                // Resources section
                section("Resources") {
                    InfoRow(label: "CPU", value: "\(machine.cpuCores) cores")
                    InfoRow(label: "Memory", value: "\(machine.memoryGB) GB")
                    InfoRow(label: "Disk", value: "\(machine.diskGB) GB")
                }

                // Network section (Inspect-only fields)
                if !machine.gateway.isEmpty || !machine.macAddress.isEmpty
                    || !machine.dnsServers.isEmpty
                {
                    section("Network") {
                        if !machine.gateway.isEmpty {
                            InfoRow(label: "Gateway", value: machine.gateway)
                        }
                        if !machine.macAddress.isEmpty {
                            InfoRow(label: "MAC Address", value: machine.macAddress)
                        }
                        if !machine.dnsServers.isEmpty {
                            InfoRow(label: "DNS", value: machine.dnsServers.joined(separator: ", "))
                        }
                    }
                }

                // Shared folders
                if !machine.mounts.isEmpty {
                    section("Shared Folders") {
                        ForEach(machine.mounts) { mount in
                            InfoRow(
                                label: mount.hostPath,
                                value: mount.readOnly
                                    ? "\(mount.guestPath) (read-only)"
                                    : mount.guestPath
                            )
                        }
                    }
                }
            }
            .padding(16)
        }
    }

    @ViewBuilder
    private func section(_ title: String, @ViewBuilder content: () -> some View) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))

            VStack(spacing: 0) {
                content()
            }
            .infoSectionStyle()
        }
    }
}
