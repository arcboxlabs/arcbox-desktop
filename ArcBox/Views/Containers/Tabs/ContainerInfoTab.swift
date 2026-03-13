import SwiftUI

/// Info tab content showing container details
struct ContainerInfoTab: View {
    let container: ContainerViewModel

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
                            ? "Up \(container.createdAgo)"
                            : "Stopped"
                    )
                }
                .infoSectionStyle()

                // Domain & IP section
                if !container.hostPorts.isEmpty || container.domain != nil
                    || container.ipAddress != nil
                {
                    VStack(spacing: 0) {
                        if !container.hostPorts.isEmpty {
                            InfoRow(
                                label: "Domain",
                                value: "localhost",
                                link: URL(string: "http://localhost:\(container.hostPorts[0])")
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
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Port Forwards")
                            .font(.system(size: 13, weight: .semibold))

                        VStack(spacing: 0) {
                            // Table header
                            HStack {
                                Text("Host Port")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("Container Port")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("Protocol")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(AppColors.surfaceElevated)

                            // Table rows
                            ForEach(container.ports) { port in
                                HStack {
                                    Text("\(port.hostPort)")
                                        .foregroundStyle(AppColors.accent)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text("\(port.containerPort)")
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(port.protocol.uppercased())
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                }
                                .font(.system(size: 13))
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .overlay(alignment: .bottom) {
                                    Divider().opacity(0.3)
                                }
                            }
                        }
                        .background(AppColors.background)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(AppColors.border, lineWidth: 0.5)
                        )
                    }
                }

                // Mounts section
                if !container.mounts.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Mounts")
                            .font(.system(size: 13, weight: .semibold))

                        VStack(spacing: 0) {
                            HStack {
                                Text("Source")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("Destination")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(AppColors.surfaceElevated)

                            ForEach(container.mounts) { mount in
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
                                .font(.system(size: 13))
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .overlay(alignment: .bottom) {
                                    Divider().opacity(0.3)
                                }
                                .textSelection(.enabled)
                            }
                        }
                        .background(AppColors.background)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(AppColors.border, lineWidth: 0.5)
                        )
                    }
                }

                // Labels section
                if !container.labels.isEmpty {
                    VStack(alignment: .leading, spacing: 8) {
                        Text("Labels")
                            .font(.system(size: 13, weight: .semibold))

                        VStack(spacing: 0) {
                            // Table header
                            HStack {
                                Text("Key")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                Text("Value")
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                            .font(.system(size: 11, weight: .medium))
                            .foregroundStyle(AppColors.textSecondary)
                            .padding(.vertical, 6)
                            .padding(.horizontal, 8)
                            .background(AppColors.surfaceElevated)

                            // Table rows
                            ForEach(
                                container.labels.sorted(by: { $0.key < $1.key }),
                                id: \.key
                            ) { key, value in
                                HStack(alignment: .top) {
                                    Text(key)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                    Text(value)
                                        .frame(maxWidth: .infinity, alignment: .leading)
                                        .lineLimit(1)
                                        .truncationMode(.tail)
                                }
                                .font(.system(size: 13))
                                .padding(.vertical, 6)
                                .padding(.horizontal, 8)
                                .overlay(alignment: .bottom) {
                                    Divider().opacity(0.3)
                                }
                                .textSelection(.enabled)
                            }
                        }
                        .background(AppColors.background)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(AppColors.border, lineWidth: 0.5)
                        )
                    }
                }
            }
            .padding(16)
        }
    }
}
