import SwiftUI

/// Platform options for pulling images
enum ImagePlatform: String, CaseIterable, Identifiable {
    case auto = "auto"
    case linuxAmd64 = "linux/amd64"
    case linuxArm64 = "linux/arm64"

    var id: String { rawValue }
}

/// Pull image dialog presented as a sheet
struct PullImageSheet: View {
    @Environment(\.dismiss) private var dismiss

    @State private var image = ""
    @State private var platform: ImagePlatform = .auto

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            VStack(alignment: .leading, spacing: 4) {
                Text("Pull Image")
                    .font(.system(size: 13, weight: .semibold))
                Text("Images are used to run containers. They contain an application and its dependencies.")
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
                    TextField("Image", text: $image, prompt: Text("e.g. alpine:latest"))
                    Picker("Platform", selection: $platform) {
                        ForEach(ImagePlatform.allCases) { p in
                            Text(p.rawValue).tag(p)
                        }
                    }
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

                Button("Pull") {
                    // TODO: pull image
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            .overlay(alignment: .top) { Divider() }
        }
        .frame(width: 480, height: 270)
    }
}
