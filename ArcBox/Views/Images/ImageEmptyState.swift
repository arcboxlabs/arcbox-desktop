import SwiftUI

struct ImageEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("No images yet")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)

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
