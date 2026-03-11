import SwiftUI

struct SandboxEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("No sandboxes yet")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)

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
            .padding(16)
            .background(
                RoundedRectangle(cornerRadius: 10)
                    .fill(AppColors.surfaceElevated)
            )

            Spacer()
        }
        .frame(maxWidth: .infinity)
        .padding(24)
    }
}
