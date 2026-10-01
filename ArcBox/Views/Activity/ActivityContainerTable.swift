import ArcBoxClient
import SwiftUI

/// Per-container resource usage, grouped by Compose project.
///
/// A native `Table` so columns sort, resize, reorder and hide the way every
/// other Mac table does, and so a row stays selected while the numbers update
/// underneath it. Sorting defaults to the busiest first, as in Activity
/// Monitor.
struct ActivityContainerTable: View {
    @Environment(AppViewModel.self) private var appVM
    @Environment(ContainersViewModel.self) private var containersVM

    let containers: [ContainerResourceStats]
    /// Docker's view of the same containers, keyed by ID. Supplies the project
    /// a row groups under and the fields search matches beyond the name. Absent
    /// while the Engine has not reported yet, which flattens the table rather
    /// than emptying it.
    let docker: [String: ActivityContainerFacts]
    let searchText: String
    /// False until the first usable frame. An empty table means "nothing is
    /// running" only once something has been read; before that it means
    /// "not known yet", and saying the first would be a guess.
    let hasLoaded: Bool

    @State private var sortOrder = [
        KeyPathComparator(\ActivityRow.displayedCPUPercent, order: .reverse)
    ]
    @State private var selection: ActivityRow.ID?
    @State private var disclosureState = ActivityRowDisclosureState()
    @State private var columnLayout = TableColumnCustomization<ActivityRow>()
    /// `TableColumnCustomization` is `Codable` but not `RawRepresentable`, so it
    /// rides in `AppStorage` as its own encoding rather than through a
    /// retroactive conformance on a type we do not own.
    @AppStorage("activity.containerColumns") private var storedColumnLayout = Data()

    var body: some View {
        // Once per sample, not once per reader: the rows and the empty state
        // both want the grouping, and it sorts every row each time it runs.
        let groups = groups
        Table(
            of: ActivityRow.self,
            selection: $selection,
            sortOrder: $sortOrder,
            columnCustomization: $columnLayout
        ) {
            TableColumn("Container", value: \.title) { row in
                title(row)
            }
            .width(min: 160, ideal: 280)
            // Hiding the column that says which row is which leaves a table of
            // anonymous numbers.
            .disabledCustomizationBehavior(.visibility)
            .customizationID("container")

            TableColumn("CPU", value: \.displayedCPUPercent) { row in
                reading(StatsFormat.percent(row.cpuPercent), isProject: row.isProject)
            }
            .width(min: 56, ideal: 68)
            .customizationID("cpu")

            TableColumn("Memory", value: \.memoryCurrentBytes) { row in
                reading(memoryReading(row), isProject: row.isProject)
            }
            .width(min: 96, ideal: 150)
            .customizationID("memory")

            TableColumn("Disk R/W", value: \.diskBytesPerSecond) { row in
                reading(
                    "\(StatsFormat.rate(row.diskReadBytesPerSecond)) / \(StatsFormat.rate(row.diskWriteBytesPerSecond))",
                    isProject: row.isProject
                )
            }
            .width(min: 120, ideal: 170)
            .customizationID("disk")

            TableColumn("Net ↓/↑", value: \.networkBytesPerSecond) { row in
                reading(
                    "\(StatsFormat.rate(row.networkReceiveBytesPerSecond)) / \(StatsFormat.rate(row.networkTransmitBytesPerSecond))",
                    isProject: row.isProject
                )
            }
            .width(min: 120, ideal: 170)
            .customizationID("network")

            TableColumn("PIDs", value: \.pids) { row in
                reading(row.pids.formatted(), isProject: row.isProject)
            }
            .width(min: 44, ideal: 56)
            .customizationID("pids")
        } rows: {
            ForEach(groups) { group in
                if group.children.isEmpty {
                    TableRow(group.summary)
                } else {
                    DisclosureTableRow(
                        group.summary,
                        isExpanded: disclosureBinding(for: group.id)
                    ) {
                        ForEach(group.children) { TableRow($0) }
                    }
                }
            }
        }
        .tableStyle(.inset)
        .alternatingRowBackgrounds()
        .overlay { emptyState(groups: groups) }
        .contextMenu(forSelectionType: ActivityRow.ID.self) { ids in
            menu(for: ids)
        } primaryAction: { ids in
            if let id = ids.first { reveal(id) }
        }
        .task { restoreColumnLayout() }
        .onChange(of: columnLayout) { _, layout in
            storedColumnLayout = (try? JSONEncoder().encode(layout)) ?? Data()
        }
    }

    /// Both empty states live here because filtering does: the view above
    /// cannot tell "nothing is running" from "nothing matches" without redoing
    /// the same work.
    @ViewBuilder
    private func emptyState(groups: [ActivityRowGroup]) -> some View {
        if !hasLoaded {
            EmptyView()
        } else if containers.isEmpty {
            ContentUnavailableView(
                "No Running Containers",
                systemImage: "cube",
                description: Text("Per-container usage appears here while containers are running.")
            )
        } else if groups.isEmpty {
            ContentUnavailableView.search(text: searchText)
        }
    }

    private var groups: [ActivityRowGroup] {
        let rows = containers.map(ActivityRow.init).filter(matchesSearch)
        return ActivityRowGrouping.groups(
            for: rows,
            projects: docker.compactMapValues(\.project),
            sortedBy: sortOrder
        )
    }

    /// Matches the Containers list: name, image and project, so a query that
    /// finds a container there finds it here too.
    private func matchesSearch(_ row: ActivityRow) -> Bool {
        guard !searchText.isEmpty else { return true }
        let query = searchText.lowercased()
        if row.title.lowercased().contains(query) { return true }
        guard let id = row.containerID, let container = docker[id] else { return false }
        return container.image.lowercased().contains(query)
            || (container.project?.lowercased().contains(query) ?? false)
    }

    private func disclosureBinding(for groupID: String) -> Binding<Bool> {
        let isFiltering = !searchText.isEmpty
        return Binding {
            disclosureState.isExpanded(groupID, isFiltering: isFiltering)
        } set: { expanded in
            disclosureState.setExpanded(
                expanded,
                for: groupID,
                isFiltering: isFiltering
            )
        }
    }

    // MARK: - Cells

    @ViewBuilder
    private func title(_ row: ActivityRow) -> some View {
        if row.isProject {
            Label(row.title, systemImage: "square.stack.3d.up")
                .font(.body.weight(.medium))
                .lineLimit(1)
        } else {
            Text(row.title)
                .lineLimit(1)
                .truncationMode(.middle)
                .help(row.containerID ?? row.title)
        }
    }

    /// Numbers read down the column, so they are trailing-aligned and share a
    /// digit width. A project's totals carry the same weight as its title.
    private func reading(_ text: String, isProject: Bool) -> some View {
        Text(text)
            .monospacedDigit()
            .fontWeight(isProject ? .medium : .regular)
            .foregroundStyle(isProject ? .primary : .secondary)
            .frame(maxWidth: .infinity, alignment: .trailing)
    }

    private func memoryReading(_ row: ActivityRow) -> String {
        guard row.memoryLimitBytes > 0 else {
            return StatsFormat.bytes(row.memoryCurrentBytes)
        }
        return "\(StatsFormat.bytes(row.memoryCurrentBytes)) / \(StatsFormat.bytes(row.memoryLimitBytes))"
    }

    // MARK: - Actions

    @ViewBuilder
    private func menu(for ids: Set<ActivityRow.ID>) -> some View {
        // Every action here addresses one container; a project row and a
        // multiple selection have no single subject.
        if ids.count == 1, let id = ids.first, docker[id] != nil {
            Button("Show in Containers") { reveal(id) }
            Button("Copy Container ID") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(id, forType: .string)
            }
        }
    }

    private func reveal(_ id: ActivityRow.ID) {
        guard docker[id] != nil else { return }
        containersVM.selectedID = id
        appVM.currentNav = .containers
    }

    // MARK: - Column layout

    /// A layout saved by a build with different columns decodes into something
    /// that no longer matches them; dropping it loses a preference, which beats
    /// restoring a table missing half its columns.
    private func restoreColumnLayout() {
        guard !storedColumnLayout.isEmpty,
            let restored = try? JSONDecoder().decode(
                TableColumnCustomization<ActivityRow>.self, from: storedColumnLayout)
        else { return }
        columnLayout = restored
    }
}
