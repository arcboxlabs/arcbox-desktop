import SwiftUI

struct MachineEmptyState: View {
    var body: some View {
        VStack(spacing: 16) {
            Spacer()

            Text("No Linux machines yet")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)

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

                Text("Click \"+ New Machine\" to get started")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
                    .padding(.top, 8)
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
