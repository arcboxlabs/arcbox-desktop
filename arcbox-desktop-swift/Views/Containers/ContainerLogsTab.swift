import SwiftUI

/// Logs tab placeholder
struct ContainerLogsTab: View {
    var body: some View {
        VStack {
            Spacer()
            Text("Logs coming soon...")
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
