import DockerClient
import OSLog
import SwiftUI

/// Inline section showing containers connected to this network
struct NetworkContainersSection: View {
    let network: NetworkViewModel

    @Environment(\.dockerClient) private var docker
    @Environment(ContainersViewModel.self) private var containersVM

    @State private var containers: [NetworkContainerEntry] = []

    var body: some View {
        VStack(spacing: 0) {
            // Section header
            HStack {
                Text("Connected Containers")
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
            }
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 6)

            // Column headers
            HStack(spacing: 0) {
                Text("Name")
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.leading, 12)
                Text("Status")
                    .frame(width: 80, alignment: .center)
                Text("IPv4 Address")
                    .frame(width: 140, alignment: .leading)
                Text("MAC Address")
                    .frame(width: 160, alignment: .leading)
            }
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(AppColors.textSecondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 6)
            .background(AppColors.surfaceElevated)

            Divider()

            if containers.isEmpty {
                Text("No containers connected")
                    .foregroundStyle(AppColors.textSecondary)
                    .font(.system(size: 13))
                    .padding(.vertical, 20)
            } else {
                LazyVStack(spacing: 0) {
                    ForEach(containers) { entry in
                        NetworkContainerRow(entry: entry)
                    }
                }
            }
        }
        .task(id: network.id) {
            await loadContainers()
        }
    }

    private func loadContainers() async {
        guard let docker else {
            containers = []
            return
        }

        do {
            let response = try await docker.api.NetworkInspect(path: .init(id: network.id))
            let networkDetail = try response.ok.body.json
            let networkContainers = networkDetail.Containers?.additionalProperties ?? [:]

            containers = networkContainers.map { (containerID, entry) in
                let isRunning =
                    containersVM.containers.first {
                        $0.id == containerID
                    }?.state == .running

                return NetworkContainerEntry(
                    name: entry.Name ?? containerID.prefix(12).description,
                    isRunning: isRunning,
                    ipv4: entry.IPv4Address ?? "",
                    mac: entry.MacAddress ?? ""
                )
            }
            .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
        } catch {
            Log.network.error(
                "Error loading containers for network \(network.id, privacy: .private): \(error.localizedDescription, privacy: .private)"
            )
            containers = []
        }
    }
}

// MARK: - Network Container Entry

struct NetworkContainerEntry: Identifiable {
    let id = UUID()
    let name: String
    let isRunning: Bool
    let ipv4: String
    let mac: String
}

// MARK: - Network Container Row

struct NetworkContainerRow: View {
    let entry: NetworkContainerEntry

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                HStack(spacing: 8) {
                    Image(systemName: "shippingbox.fill")
                        .font(.system(size: 14))
                        .foregroundStyle(AppColors.textSecondary)
                    Text(entry.name)
                        .font(.system(size: 13))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.leading, 12)

                HStack(spacing: 6) {
                    Circle()
                        .fill(entry.isRunning ? Color.green : Color.gray)
                        .frame(width: 8, height: 8)
                    Text(entry.isRunning ? "Running" : "Stopped")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .frame(width: 80, alignment: .center)

                Text(entry.ipv4)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 140, alignment: .leading)

                Text(entry.mac)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(AppColors.textSecondary)
                    .frame(width: 160, alignment: .leading)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 6)

            Divider().opacity(0.2)
        }
    }
}
