import SwiftUI

/// Files tab placeholder for machines
struct MachineFilesTab: View {
    let machine: MachineViewModel

    var body: some View {
        VStack {
            Spacer()
            Image(systemName: "folder")
                .font(.system(size: 32))
                .foregroundStyle(AppColors.textMuted)
            Text("Files")
                .font(.system(size: 15))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.top, 8)
            Text("Machine file browser will appear here.")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
