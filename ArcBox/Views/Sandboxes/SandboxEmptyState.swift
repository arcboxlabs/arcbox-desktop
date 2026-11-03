import SwiftUI

struct SandboxEmptyState: View {
    var body: some View {
        EmptyStateView(icon: "shippingbox", title: "No sandboxes yet") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Create a sandbox:")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)

                CommandHint(
                    command: "abctl sandbox create",
                    description: "Create with the built-in minimal template"
                )
                CommandHint(
                    command: "abctl sandbox create --from-image <ref>",
                    description: "Create from a local Docker image"
                )
            }
        }
    }
}

/// Fills the sandbox list on a Mac whose hardware or System VM backend cannot run
/// sandboxes. Nothing to retry: only another backend or another Mac changes it.
struct SandboxesUnsupportedView: View {
    /// The daemon's `nested_virt.reason`, a lowercase clause such as "nested
    /// virtualization requires Apple Silicon M3 or newer with macOS 15 or newer".
    let reason: String

    var body: some View {
        ContentUnavailableView {
            Label("This Mac Can’t Run Sandboxes", systemImage: "cpu")
        } description: {
            Text(sentence)
        }
    }

    private var sentence: String {
        guard let first = reason.first else { return reason }
        let sentence = first.uppercased() + reason.dropFirst()
        return sentence.hasSuffix(".") ? sentence : sentence + "."
    }
}
