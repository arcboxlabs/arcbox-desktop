import SwiftUI

struct SandboxEmptyState: View {
    var body: some View {
        EmptyStateView(icon: "shippingbox", title: "No sandboxes yet") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Create a sandbox:")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)

                CommandHint(
                    command: "e2b sandbox create",
                    description: "Create from default template"
                )
                CommandHint(
                    command: "e2b sandbox create --template <id>",
                    description: "Create from specific template"
                )
            }
        }
    }
}
