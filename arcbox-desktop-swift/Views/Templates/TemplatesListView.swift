import SwiftUI

/// Column 2: templates list with toolbar
struct TemplatesListView: View {
    @Environment(TemplatesViewModel.self) private var vm

    var body: some View {
        VStack(spacing: 0) {
            if vm.templates.isEmpty {
                TemplateEmptyState()
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(vm.sortedTemplates) { template in
                            TemplateRowView(
                                template: template,
                                isSelected: vm.selectedID == template.id,
                                onSelect: { vm.selectTemplate(template.id) }
                            )
                        }
                    }
                }
            }
        }
        .navigationTitle("Templates")
        .navigationSubtitle("\(vm.templateCount) total")
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                SortMenuButton(sortBy: Bindable(vm).sortBy, ascending: Bindable(vm).sortAscending)
                Button(action: {}) {
                    Image(systemName: "magnifyingglass")
                }
                Button(action: {}) {
                    Image(systemName: "plus")
                }
            }
        }
        .onAppear { vm.loadSampleData() }
    }
}
