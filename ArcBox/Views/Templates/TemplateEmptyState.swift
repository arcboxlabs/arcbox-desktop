import SwiftUI

struct TemplateEmptyState: View {
    var body: some View {
        EmptyStateView(icon: "doc.text", title: "No templates yet") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Create a template:")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)

                CommandHint(
                    command: "arcbox template init",
                    description: "Initialize a new template"
                )
                CommandHint(
                    command: "arcbox template build",
                    description: "Build template from Dockerfile"
                )
            }
        }
    }
}
