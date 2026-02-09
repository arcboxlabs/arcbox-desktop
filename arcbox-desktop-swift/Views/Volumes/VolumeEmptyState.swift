import SwiftUI

struct VolumeEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("No volumes yet")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Create a volume:")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)

                CommandHint(
                    command: "docker volume create mydata",
                    description: "Create named volume"
                )
                CommandHint(
                    command: "docker run -v mydata:/data nginx",
                    description: "Mount volume to container"
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
