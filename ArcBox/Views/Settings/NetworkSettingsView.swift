import SwiftUI

enum ProxyMode: String, CaseIterable, Identifiable {
    case auto = "Auto (system)"
    case custom = "Custom"
    case none = "None"

    var id: String { rawValue }
}

struct NetworkSettingsView: View {
    @State private var proxyMode: ProxyMode = .auto
    @State private var allowContainerDomains = true
    @State private var enableHTTPS = true
    @State private var ipRange = "192.168.138.0/23"

    private let ipRangeOptions = [
        "192.168.138.0/23",
        "172.16.0.0/12",
        "10.0.0.0/8",
    ]

    var body: some View {
        Form {
            Section("Proxy") {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Apply an HTTP, HTTPS, or SOCKS proxy to all traffic from containers and machines.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .padding(.bottom, 4)

                    Picker("", selection: $proxyMode) {
                        ForEach(ProxyMode.allCases) { mode in
                            Text(mode.rawValue).tag(mode)
                        }
                    }
                    .pickerStyle(.radioGroup)
                    .labelsHidden()
                }
            }

            Section("Domains") {
                LabeledContent {
                    Toggle("", isOn: $allowContainerDomains)
                        .labelsHidden()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Allow access to container domains & IPs")
                        Text(
                            "Use domains and IPs to connect to containers and machines without port forwarding. [Learn more](#)"
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
                }

                Toggle("Enable HTTPS for container domains", isOn: $enableHTTPS)

                LabeledContent {
                    Picker("", selection: $ipRange) {
                        ForEach(ipRangeOptions, id: \.self) { option in
                            if option == "192.168.138.0/23" {
                                Text("\(option) (default)").tag(option)
                            } else {
                                Text(option).tag(option)
                            }
                        }
                    }
                    .labelsHidden()
                    .frame(width: 220)
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("IP range")
                        Text(
                            "Used for domains and machines. Containers and Kubernetes use different IPs. Don't change this unless you run into issues with the default."
                        )
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    }
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
}

#Preview {
    NetworkSettingsView()
        .frame(width: 500, height: 600)
}
