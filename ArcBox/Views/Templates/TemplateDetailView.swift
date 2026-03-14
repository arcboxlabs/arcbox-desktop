import SwiftUI

/// Column 3: template detail with tab-based toolbar
struct TemplateDetailView: View {
    @Environment(TemplatesViewModel.self) private var vm

    var body: some View {
        @Bindable var vm = vm
        let template = vm.selectedTemplate

        VStack(spacing: 0) {
            if let template {
                switch vm.activeTab {
                case .info:
                    ScrollView {
                        VStack(spacing: 0) {
                            InfoRow(label: "Name", value: template.name)
                            InfoRow(label: "ID", value: template.shortID)
                            InfoRow(label: "CPU", value: template.cpuDisplay)
                            InfoRow(label: "Memory", value: template.memoryDisplay)
                            InfoRow(label: "Created", value: template.createdAgo)
                            InfoRow(label: "Updated", value: template.updatedAgo)
                            InfoRow(label: "Sandboxes", value: template.sandboxCountDisplay)
                        }
                        .infoSectionStyle()
                        .padding(16)
                    }
                case .sandboxes:
                    Spacer()
                    Text("Sandboxes coming soon...")
                        .foregroundStyle(AppColors.textSecondary)
                    Spacer()
                }
            } else {
                Spacer()
                Text("No Selection")
                    .foregroundStyle(AppColors.textSecondary)
                    .font(.system(size: 15))
                Spacer()
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .toolbar {
            ToolbarItem(placement: .principal) {
                Picker("Tab", selection: $vm.activeTab) {
                    ForEach(TemplateDetailTab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 200)
            }
        }
    }
}
