import SwiftUI

struct StorageSettingsView: View {
    @State private var storageLocation = "default"
    @State private var includeTimeMachine = false
    @State private var hideOrbStackVolume = false

    private let locationOptions = [
        ("default", "Default"),
        ("custom", "Custom..."),
    ]

    var body: some View {
        Form {
            Section("Data") {
                LabeledContent("Location") {
                    Picker("", selection: $storageLocation) {
                        ForEach(locationOptions, id: \.0) { option in
                            Text(option.1).tag(option.0)
                        }
                    }
                    .labelsHidden()
                    .frame(width: 120)
                }

                Toggle("Include data in Time Machine backups", isOn: $includeTimeMachine)
            }

            Section("Integration") {
                LabeledContent {
                    Toggle("", isOn: $hideOrbStackVolume)
                        .labelsHidden()
                } label: {
                    VStack(alignment: .leading, spacing: 2) {
                        Text("Hide OrbStack volume from Finder & Desktop")
                        Text("This volume makes it easy to access files in containers and machines.")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            Section("Danger Zone") {
                Button("Reset Docker Data") {}
                Button("Reset Kubernetes Cluster") {}
                Button("Reset All Data") {}
            }

            Section {
                HStack {
                    Spacer()
                    Button("Apply and Restart") {}
                        .disabled(true)
                    Spacer()
                }
            }
            .listRowBackground(Color.clear)
        }
        .formStyle(.grouped)
        .scrollContentBackground(.hidden)
    }
}

#Preview {
    StorageSettingsView()
        .frame(width: 500, height: 600)
}
