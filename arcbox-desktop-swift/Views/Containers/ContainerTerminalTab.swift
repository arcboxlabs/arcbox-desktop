import SwiftUI

/// Terminal tab placeholder
struct ContainerTerminalTab: View {
    var body: some View {
        VStack {
            Spacer()
            Text("Terminal coming soon...")
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
