import ArcBoxClient
import SwiftUI

/// A label key-value pair for use in InfoTableView
private struct LabelEntry: Identifiable {
    let key: String
    let value: String
    var id: String { key }
}

/// Info tab content showing container details
struct ContainerInfoTab: View {
    let container: ContainerViewModel
    @Environment(DaemonManager.self) private var daemonManager

    private var useDNS: Bool { daemonManager.dnsResolverInstalled && daemonManager.routeInstalled }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                // Basic info section
                VStack(spacing: 0) {
                    InfoRow(label: "Name", value: container.name)
                    InfoRow(label: "ID", value: container.id)
                    InfoRow(label: "Image", value: container.image)
                    InfoRow(
                        label: "Status",
                        value: container.isRunning
                            ? "Up \(container.uptimeDisplay)"
                            : "Stopped"
                    )
                }
                .infoSectionStyle()

                // Domain & IP section
                if useDNS || !container.hostPorts.isEmpty
                    || container.domain != nil || container.ipAddress != nil
                {
                    VStack(spacing: 0) {
                        if useDNS || !container.hostPorts.isEmpty {
                            InfoRow(
                                label: "Domain",
                                value: container.hostDomain(useDNS: useDNS),
                                link: container.domainURL(useDNS: useDNS)
                            )
                        } else if let domain = container.domain {
                            InfoRow(label: "Domain", value: domain)
                        }
                        if let ip = container.ipAddress {
                            InfoRow(label: "IP", value: ip)
                        }
                    }
                    .infoSectionStyle()
                }

                // Port Forwards section
                if !container.ports.isEmpty {
                    InfoTableView(
                        title: "Port Forwards",
                        columns: ["Host Port", "Container Port", "Protocol"],
                        items: container.ports
                    ) { port in
                        HStack {
                            Text(verbatim: "\(port.hostPort)")
                                .foregroundStyle(AppColors.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(verbatim: "\(port.containerPort)")
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(port.protocol.uppercased())
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }

                // Mounts section
                if !container.mounts.isEmpty {
                    InfoTableView(
                        title: "Mounts",
                        columns: ["Source", "Destination"],
                        items: container.mounts
                    ) { mount in
                        HStack(alignment: .top) {
                            Text(mount.source)
                                .foregroundStyle(AppColors.accent)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            Text(mount.destination)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                        .textSelection(.enabled)
                    }
                }

                // Labels section
                if !container.labels.isEmpty {
                    InfoTableView(
                        title: "Labels",
                        columns: ["Key", "Value"],
                        items: container.labels.sorted(by: { $0.key < $1.key }).map {
                            LabelEntry(key: $0.key, value: $0.value)
                        }
                    ) { entry in
                        HStack(alignment: .top) {
                            Text(entry.key)
                                .frame(maxWidth: .infinity, alignment: .leading)
                            Text(entry.value)
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .lineLimit(1)
                                .truncationMode(.tail)
                        }
                        .textSelection(.enabled)
                    }
                }
            }
            .padding(16)
        }
    }
}
