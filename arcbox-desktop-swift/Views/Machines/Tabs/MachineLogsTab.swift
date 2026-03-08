import SwiftUI

/// Logs tab placeholder for machines
struct MachineLogsTab: View {
    let machine: MachineViewModel

    var body: some View {
        VStack {
            Spacer()
            Image(systemName: "doc.text")
                .font(.system(size: 32))
                .foregroundStyle(AppColors.textMuted)
            Text("Logs")
                .font(.system(size: 15))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.top, 8)
            Text("Machine logs will appear here.")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
