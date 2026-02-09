import SwiftUI

/// Files tab placeholder
struct ContainerFilesTab: View {
    var body: some View {
        VStack {
            Spacer()
            Text("File browser coming soon...")
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
