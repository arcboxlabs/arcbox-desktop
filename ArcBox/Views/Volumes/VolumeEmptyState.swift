import SwiftUI

struct VolumeEmptyState: View {
    var body: some View {
        EmptyStateView(icon: "internaldrive", title: "No volumes yet") {
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
        }
    }
}
