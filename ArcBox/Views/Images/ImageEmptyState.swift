import SwiftUI

struct ImageEmptyState: View {
    var body: some View {
        EmptyStateView(icon: "circle.circle", title: "No images yet") {
            VStack(alignment: .leading, spacing: 8) {
                Text("Pull an image:")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)

                CommandHint(
                    command: "docker pull nginx",
                    description: "Official nginx image"
                )
                CommandHint(
                    command: "docker pull postgres:16",
                    description: "PostgreSQL database"
                )
                CommandHint(
                    command: "docker pull redis:alpine",
                    description: "Redis with Alpine Linux"
                )
            }
        }
    }
}
