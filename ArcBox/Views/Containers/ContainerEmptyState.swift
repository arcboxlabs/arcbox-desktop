import SwiftUI

/// "No containers yet" + quick start commands
struct ContainerEmptyState: View {
    var body: some View {
        EmptyStateView(icon: "cube", title: "No containers yet") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Quick start:")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)

                CommandHint(
                    command: "docker run -d nginx",
                    description: "Run nginx server"
                )
                CommandHint(
                    command: "docker run -it ubuntu bash",
                    description: "Interactive Ubuntu shell"
                )
                CommandHint(
                    command: "docker compose up -d",
                    description: "Start compose project"
                )
            }
        }
    }
}
