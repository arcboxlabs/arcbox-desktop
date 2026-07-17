import SwiftUI

/// Accepts a Fleet enrollment token without requiring an ArcBox sign-in.
struct ManualFleetEnrollmentSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(RunnersViewModel.self) private var vm

    @State private var enrollmentToken = ""
    @State private var isSubmitting = false
    @State private var errorMessage: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 6) {
                Text("Enroll with a Token")
                    .font(.title2)
                    .bold()
                Text(
                    "Paste a Fleet enrollment token from the ArcBox web dashboard. "
                        + "Signing in to the Desktop app is not required."
                )
                .foregroundStyle(.secondary)
            }

            SecureField("Fleet enrollment token", text: $enrollmentToken)
                .textFieldStyle(.roundedBorder)
                .accessibilityHint("Paste the enrollment token copied from the ArcBox web dashboard")

            if let errorMessage {
                Label(errorMessage, systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(AppColors.warning)
            }

            HStack {
                Spacer()
                Button("Cancel", action: dismiss.callAsFunction)
                    .keyboardShortcut(.cancelAction)
                    .disabled(isSubmitting)
                Button(action: enroll) {
                    if isSubmitting {
                        ProgressView()
                            .controlSize(.small)
                    } else {
                        Text("Enroll")
                    }
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(normalizedToken.isEmpty || isSubmitting || vm.isBusy)
                .accessibilityLabel(isSubmitting ? "Enrolling this Mac" : "Enroll this Mac")
            }
        }
        .padding(22)
        .frame(width: 460)
    }

    private var normalizedToken: String {
        enrollmentToken.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func enroll() {
        let token = normalizedToken
        guard !token.isEmpty else { return }

        enrollmentToken = ""
        errorMessage = nil
        isSubmitting = true
        Task {
            let succeeded = await vm.enroll(withToken: token)
            isSubmitting = false
            if succeeded {
                dismiss()
            } else {
                errorMessage = vm.errorMessage ?? "Fleet enrollment failed."
            }
        }
    }
}
