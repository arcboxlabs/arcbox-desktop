import AppKit
import ArcBoxClient
import SwiftUI

/// Ports tab: expose sandbox ports on the host (loopback) and remove mappings.
///
/// sandbox.v1 has no RPC to enumerate mappings, so the list shows only ports
/// exposed from this app session; the daemon removes all mappings on
/// Stop/Remove.
struct SandboxPortsTab: View {
    let sandbox: SandboxViewModel

    @Environment(SandboxesViewModel.self) private var vm
    @Environment(\.arcboxClient) private var client

    @State private var sandboxPortText = ""
    @State private var hostPortText = ""
    @State private var networkProtocol = "tcp"
    @State private var isWorking = false

    private var mappings: [SandboxExposedPort] {
        vm.exposedPorts[sandbox.id] ?? []
    }

    var body: some View {
        VStack(spacing: 0) {
            toolbar
            Divider()
            content
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
    }

    private var toolbar: some View {
        HStack(spacing: 10) {
            TextField("Sandbox port", text: $sandboxPortText, prompt: Text("8080"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)

            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundStyle(AppColors.textSecondary)

            TextField("Host port", text: $hostPortText, prompt: Text("auto"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)

            Picker("", selection: $networkProtocol) {
                Text("TCP").tag("tcp")
                Text("UDP").tag("udp")
            }
            .pickerStyle(.segmented)
            .frame(width: 110)

            Spacer()

            Button("Expose", action: expose)
                .disabled(!canExpose)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    @ViewBuilder
    private var content: some View {
        if mappings.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "network")
                    .font(.system(size: 24))
                    .foregroundStyle(AppColors.textMuted)
                Text("No ports exposed from this session.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                Text("Host listeners bind on localhost. Mappings created by the CLI or SDK are not listed here.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(mappings) { mapping in
                        mappingRow(mapping)
                        Divider()
                    }
                }
            }
        }
    }

    private func mappingRow(_ mapping: SandboxExposedPort) -> some View {
        HStack(spacing: 10) {
            Text("\(mapping.networkProtocol.uppercased()) \(mapping.sandboxPort)")
                .font(.system(size: 12, design: .monospaced))

            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundStyle(AppColors.textSecondary)

            if mapping.networkProtocol == "tcp", let url = mapping.localURL {
                Link("localhost:\(mapping.hostPort)", destination: url)
                    .font(.system(size: 12, design: .monospaced))
                    .help("Open in browser")
            } else {
                Text("localhost:\(mapping.hostPort)")
                    .font(.system(size: 12, design: .monospaced))
            }

            Text("via guest \(mapping.guestPort)")
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textMuted)

            Spacer()

            Button {
                unexpose(mapping)
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(AppColors.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Remove mapping")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private var canExpose: Bool {
        guard !isWorking, client != nil else { return false }
        guard let port = UInt32(sandboxPortText), port > 0, port < 65536 else { return false }
        if !hostPortText.isEmpty {
            guard let host = UInt32(hostPortText), host > 0, host < 65536 else { return false }
        }
        return true
    }

    private func expose() {
        guard let port = UInt32(sandboxPortText) else { return }
        let hostPort = UInt32(hostPortText) ?? 0
        isWorking = true
        Task {
            _ = await vm.exposePort(
                sandboxID: sandbox.id,
                sandboxPort: port,
                hostPort: hostPort,
                networkProtocol: networkProtocol,
                client: client
            )
            isWorking = false
        }
    }

    private func unexpose(_ mapping: SandboxExposedPort) {
        isWorking = true
        Task {
            await vm.unexposePort(
                sandboxID: sandbox.id,
                sandboxPort: mapping.sandboxPort,
                networkProtocol: mapping.networkProtocol,
                client: client
            )
            isWorking = false
        }
    }
}
