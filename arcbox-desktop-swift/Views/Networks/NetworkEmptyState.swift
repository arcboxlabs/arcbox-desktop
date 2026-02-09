import SwiftUI

struct NetworkEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("No networks yet")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)

            VStack(alignment: .leading, spacing: 8) {
                Text("Create a network:")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)

                CommandHint(
                    command: "docker network create mynet",
                    description: "Create bridge network"
                )
                CommandHint(
                    command: "docker network create --driver overlay mynet",
                    description: "Create overlay network"
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
