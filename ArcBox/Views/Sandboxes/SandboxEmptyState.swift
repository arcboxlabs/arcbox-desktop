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
                    description: "Create with the default rootfs"
                )
                CommandHint(
                    command: "abctl sandbox create --from-image <ref>",
                    description: "Create from a local Docker image"
                )
            }
        }
    }
}
