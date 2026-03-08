import SwiftUI

/// Terminal tab placeholder for machines
struct MachineTerminalTab: View {
    let machine: MachineViewModel

    var body: some View {
        VStack {
            Spacer()
            Image(systemName: "terminal")
                .font(.system(size: 32))
                .foregroundStyle(AppColors.textMuted)
            Text("Terminal")
                .font(.system(size: 15))
                .foregroundStyle(AppColors.textSecondary)
                .padding(.top, 8)
            Text("Machine terminal will appear here.")
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textMuted)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
