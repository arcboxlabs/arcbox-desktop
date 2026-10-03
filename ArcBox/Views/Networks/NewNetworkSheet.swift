import DockerClient
import SwiftUI

/// New network dialog presented as a sheet
struct NewNetworkSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dockerClient) private var docker
    @Environment(NetworksViewModel.self) private var vm

    @State private var name = ""
    @State private var enableIPv6 = false
    @State private var isCreating = false
    /// Copied out of the view model rather than observed: the list behind this sheet has an
    /// `.errorToast` on the same `lastError`, and the toast clears it after four seconds even
    /// though it is hidden — which would wipe this message while the form is still open.
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 6) {
                Text("New Network")
                    .font(.system(size: 20, weight: .semibold))
                Text(
                    "Networks are groups of containers in the same subnet (IP range) that can communicate with each other. "
                        + "They are typically used by Compose, and don't need to be manually created or deleted."
                )
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                SheetErrorMessage(message: errorMessage)
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
                .disabled(isCreating)

            VStack(alignment: .leading, spacing: 14) {
                Text("Advanced")
                    .font(.system(size: 14, weight: .semibold))

                VStack(spacing: 0) {
                    HStack {
                        Text("IPv6")
                            .font(.system(size: 14))
                        Spacer()
                        Toggle("IPv6", isOn: $enableIPv6)
                            .labelsHidden()
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
            .disabled(isCreating)

            Spacer(minLength: 0)

            HStack(spacing: 10) {
                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .buttonStyle(.bordered)
                .keyboardShortcut(.cancelAction)
                .disabled(isCreating)

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
        .interactiveDismissDisabled(isCreating)
    }

    private func createNetwork() {
        guard !isCreating else { return }
        isCreating = true
        Task {
            let ok = await vm.createNetwork(name: name, enableIPv6: enableIPv6, docker: docker)
            isCreating = false
            if ok { dismiss() } else { errorMessage = vm.lastError }
        }
    }
}
