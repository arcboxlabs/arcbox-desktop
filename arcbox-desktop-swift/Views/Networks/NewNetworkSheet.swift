import SwiftUI
import DockerClient

/// New network dialog presented as a sheet
struct NewNetworkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dockerClient) private var docker
    @Environment(NetworksViewModel.self) private var vm

    @State private var name = ""
    @State private var enableIPv6 = false
    @State private var isCreating = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("New Network")
                    .font(.system(size: 20, weight: .semibold))
                Text("Networks are groups of containers in the same subnet (IP range) that can communicate with each other. They are typically used by Compose, and don't need to be manually created or deleted.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
                if let errorMessage {
                    Text(errorMessage)
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.error)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(.bottom, 22)

            TextField("Name", text: $name)
                .textFieldStyle(.plain)
                .font(.system(size: 18))
                .padding(.horizontal, 16)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppColors.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.border)
                )
                .padding(.bottom, 32)

            VStack(alignment: .leading, spacing: 14) {
                Text("Advanced")
                    .font(.system(size: 14, weight: .semibold))

                VStack(spacing: 0) {
                    HStack {
                        Text("IPv6")
                            .font(.system(size: 14))
                        Spacer()
                        Toggle("", isOn: $enableIPv6)
                            .labelsHidden()
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)

                    Divider()

                    HStack {
                        Text("Subnet (IPv4)")
                            .font(.system(size: 14))
                        Spacer()
                        Text("172.30.30.0/24")
                            .font(.system(size: 14))
                            .foregroundStyle(AppColors.textMuted)
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 14)
                }
                .background(
                    RoundedRectangle(cornerRadius: 12)
                        .fill(AppColors.surface)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 12)
                        .stroke(AppColors.border)
                )
            }
            .padding(.bottom, 20)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Button(action: {}) {
                    Image(systemName: "questionmark")
                        .font(.system(size: 18, weight: .semibold))
                        .foregroundStyle(AppColors.textSecondary)
                        .frame(width: 40, height: 40)
                        .background(Circle().fill(AppColors.surface))
                        .overlay(Circle().stroke(AppColors.border))
                }
                .buttonStyle(.plain)

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    createNetwork()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isCreating)
            }
        }
        .padding(.horizontal, 22)
        .padding(.top, 22)
        .padding(.bottom, 18)
        .frame(width: 640, height: 430)
    }

    private func createNetwork() {
        errorMessage = nil
        isCreating = true

        Task {
            let failure = await vm.createNetwork(name: name, enableIPv6: enableIPv6, docker: docker)
            await MainActor.run {
                isCreating = false
                if let failure {
                    errorMessage = failure
                } else {
                    dismiss()
                }
            }
        }
    }
}
