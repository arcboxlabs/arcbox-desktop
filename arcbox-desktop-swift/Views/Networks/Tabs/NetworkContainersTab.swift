import SwiftUI

/// Containers tab showing containers connected to this network
struct NetworkContainersTab: View {
    let network: NetworkViewModel

    @State private var containers: [NetworkContainerEntry] = []

    var body: some View {
        VStack(spacing: 0) {
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
                Spacer()
                Text("No containers connected")
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(containers) { entry in
                            NetworkContainerRow(entry: entry)
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .onAppear {
            loadSampleContainers()
        }
    }

    private func loadSampleContainers() {
        switch network.name {
        case "bridge":
            containers = [
                NetworkContainerEntry(
                    name: "web-frontend", isRunning: true,
                    ipv4: "172.17.0.2/16", mac: "02:42:ac:11:00:02"),
                NetworkContainerEntry(
                    name: "redis-cache", isRunning: false,
                    ipv4: "172.17.0.3/16", mac: "02:42:ac:11:00:03"),
            ]
        case "myapp_default":
            containers = [
                NetworkContainerEntry(
                    name: "web-frontend", isRunning: true,
                    ipv4: "192.168.215.2/24", mac: "02:42:c0:a8:d7:02"),
                NetworkContainerEntry(
                    name: "api-server", isRunning: true,
                    ipv4: "192.168.215.3/24", mac: "02:42:c0:a8:d7:03"),
                NetworkContainerEntry(
                    name: "postgres-db", isRunning: true,
                    ipv4: "192.168.215.4/24", mac: "02:42:c0:a8:d7:04"),
            ]
        default:
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
