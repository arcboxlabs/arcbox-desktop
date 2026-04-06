import SwiftUI

struct MachineEmptyState: View {
    var body: some View {
        EmptyStateView(icon: "desktopcomputer", title: "No Linux machines yet") {
            VStack(alignment: .leading, spacing: 12) {
                Text("Create a new machine to run a full Linux environment:")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)

                VStack(alignment: .leading, spacing: 4) {
                    Text("\u{2022} Ubuntu, Debian, Fedora, and more")
                    Text("\u{2022} Native ARM64 performance on Apple Silicon")
                    Text("\u{2022} Seamless file sharing with macOS")
                }
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textSecondary)

                Text("Click \"+\" in the toolbar to get started")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.top, 8)
            }
        }
    }
}
