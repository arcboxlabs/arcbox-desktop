import SwiftUI

/// New network dialog presented as a sheet
struct NewNetworkSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var enableIPv6 = false
    @State private var subnet = ""

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            VStack(alignment: .leading, spacing: 4) {
                Text("New Network")
                    .font(.system(size: 13, weight: .semibold))
                Text("Networks are groups of containers in the same subnet (IP range) that can communicate with each other. They are typically used by Compose, and don't need to be manually created or deleted.")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Divider() }

            // Form
            Form {
                Section {
                    TextField("Name", text: $name)
                }

                Section("Advanced") {
                    Toggle("IPv6", isOn: $enableIPv6)
                    TextField("Subnet (IPv4)", text: $subnet, prompt: Text("172.30.30.0/24"))
                }
            }
            .formStyle(.grouped)

            // Footer buttons
            HStack {
                Button("?") {}
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    // TODO: create network
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(alignment: .top) { Divider() }
        }
        .frame(width: 480, height: 360)
    }
}
