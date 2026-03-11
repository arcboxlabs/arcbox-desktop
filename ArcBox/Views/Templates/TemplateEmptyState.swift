import SwiftUI

struct TemplateEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("No templates yet")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Create a template:")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)

                CommandHint(
                    command: "e2b template init",
                    description: "Initialize a new template"
                )
                CommandHint(
                    command: "e2b template build",
                    description: "Build template from Dockerfile"
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
