import SwiftUI

struct NetworkEmptyState: View {
    var body: some View {
        EmptyStateView(
            icon: "point.3.filled.connected.trianglepath.dotted",
            title: "No networks yet"
        ) {
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
        }
    }
}
