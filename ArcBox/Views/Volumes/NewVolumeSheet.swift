import SwiftUI

/// New volume dialog presented as a sheet
struct NewVolumeSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            VStack(alignment: .leading, spacing: 4) {
                Text("New Volume")
                    .font(.system(size: 13, weight: .semibold))
                Text("Volumes are for sharing data between containers. Unlike bind mounts, they are stored on a native Linux file system, making them faster and more reliable.")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay(alignment: .bottom) { Divider() }

            // Form
            Form {
                Section {
                    TextField("Name", text: $name)
                }
            }
            .formStyle(.grouped)

            // Footer buttons
            HStack {
                Button("?") {}
                    .buttonStyle(.plain)
                    .frame(width: 24, height: 24)

                Button("Import...") {}

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Create") {
                    // TODO: create volume
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(alignment: .top) { Divider() }
        }
        .frame(width: 480, height: 240)
    }
}
