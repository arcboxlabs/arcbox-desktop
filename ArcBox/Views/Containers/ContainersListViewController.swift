import AppKit
import Foundation
import Observation

@MainActor
final class ContainersListViewController: NSViewController,
    NSOutlineViewDataSource,
    NSOutlineViewDelegate,
    NSMenuDelegate
{
    struct Actions {
        let retry: @MainActor () -> Void
        let select: @MainActor (String) -> Void
        let toggle: @MainActor (String) -> Void
        let delete: @MainActor (String) -> Void
        let toggleGroup: @MainActor (String, [String]) -> Void
        let deleteGroup: @MainActor (String, [String]) -> Void
    }

    private static let sectionCellIdentifier = NSUserInterfaceItemIdentifier(
        "ContainerSectionCell"
    )
    private static let composeCellIdentifier = NSUserInterfaceItemIdentifier(
        "ContainerComposeCell"
    )
    private static let containerCellIdentifier = NSUserInterfaceItemIdentifier(
        "ContainerCell"
    )

    private let viewModel: ContainersViewModel
    private let scrollView = NSScrollView()
    private let outlineView = ContainersOutlineView()
    private let placeholderView = StatePlaceholderView(
        state: .loading(title: "Loading containers…")
    )
    private let emptyStateView = CommandEmptyStateView(
        systemImage: "cube",
        title: "No containers yet",
        prompt: "Quick start:",
        commands: [
            .init(command: "docker run -d nginx", description: "Run nginx server"),
            .init(command: "docker run -it ubuntu bash", description: "Interactive Ubuntu shell"),
            .init(command: "docker compose up -d", description: "Start compose project"),
        ]
    )

    private var snapshot: ContainerListSnapshot?
    private let tree = ContainerListTree()
    private var loadingTitle: String
    private var useDNS: Bool
    private var actions: Actions
    private var contextContainerID: String?
    private var contextToggleItem: NSMenuItem?
    private var contextCopyNameItem: NSMenuItem?
    private var contextCopyIDItem: NSMenuItem?
    private var contextDeleteItem: NSMenuItem?
    private var deleteAlert: NSAlert?
    private var isApplyingExpansion = false
    private var isApplyingSelection = false

    #if DEBUG
        /// Completed `render` passes, and a hook that fires after each one;
        /// tests use them to await and time a single snapshot update.
        private(set) var renderCount = 0
        var renderObserver: (@MainActor () -> Void)?
    #endif

    init(
        viewModel: ContainersViewModel,
        loadingTitle: String,
        useDNS: Bool,
        actions: Actions
    ) {
        self.viewModel = viewModel
        self.loadingTitle = loadingTitle
        self.useDNS = useDNS
        self.actions = actions
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView()
        setUpOutlineView()

        let fills: [(view: NSView, topInset: CGFloat)] = [
            (scrollView, 6), (placeholderView, 0), (emptyStateView, 0),
        ]
        for (subview, topInset) in fills {
            subview.translatesAutoresizingMaskIntoConstraints = false
            container.addSubview(subview)
            NSLayoutConstraint.activate([
                subview.leadingAnchor.constraint(equalTo: container.leadingAnchor),
                subview.trailingAnchor.constraint(equalTo: container.trailingAnchor),
                subview.topAnchor.constraint(equalTo: container.topAnchor, constant: topInset),
                subview.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            ])
        }
        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observeAndRender()
    }

    func update(
        loadingTitle: String,
        useDNS: Bool,
        actions: Actions
    ) {
        let loadingTitleChanged = self.loadingTitle != loadingTitle
        let useDNSChanged = self.useDNS != useDNS
        self.loadingTitle = loadingTitle
        self.useDNS = useDNS
        self.actions = actions

        guard let snapshot, isViewLoaded else { return }
        switch snapshot.loadState {
        case .waiting, .loading:
            if loadingTitleChanged {
                placeholderView.update(.loading(title: loadingTitle))
                NSAccessibility.post(
                    element: placeholderView,
                    notification: .layoutChanged
                )
            }
        case .failed(let message):
            placeholderView.update(
                .error(title: "Failed to load containers", message: message),
                action: .init(title: "Retry", handler: actions.retry)
            )
        case .loaded:
            if useDNSChanged {
                reconfigureVisibleContainerCells()
            }
        }
    }

    func outlineView(
        _: NSOutlineView,
        numberOfChildrenOfItem item: Any?
    ) -> Int {
        guard let item = item as? ContainerListNode else {
            return tree.roots.count
        }
        return item.children.count
    }

    func outlineView(
        _: NSOutlineView,
        child index: Int,
        ofItem item: Any?
    ) -> Any {
        guard let item = item as? ContainerListNode else {
            return tree.roots[index]
        }
        return item.children[index]
    }

    func outlineView(
        _: NSOutlineView,
        isItemExpandable item: Any
    ) -> Bool {
        guard let item = item as? ContainerListNode else { return false }
        if case .compose = item.presentation {
            return true
        }
        return false
    }

    func outlineView(
        _: NSOutlineView,
        viewFor _: NSTableColumn?,
        item: Any
    ) -> NSView? {
        guard let node = item as? ContainerListNode else { return nil }
        let cell = dequeueCell(for: node.presentation)
        configure(cell, for: node.presentation)
        return cell
    }

    func outlineView(_: NSOutlineView, isGroupItem item: Any) -> Bool {
        guard
            let item = item as? ContainerListNode,
            case .section = item.presentation
        else {
            return false
        }
        return true
    }

    func outlineView(
        _: NSOutlineView,
        heightOfRowByItem item: Any
    ) -> CGFloat {
        guard let item = item as? ContainerListNode else { return 0 }
        if case .section = item.presentation {
            return 28
        }
        return AppMetrics.rowHeight
    }

    func outlineView(
        _: NSOutlineView,
        rowViewForItem item: Any
    ) -> NSTableRowView? {
        guard let item = item as? ContainerListNode else { return nil }
        if case .section = item.presentation {
            return nil
        }
        return ResourceListRowView(horizontalInset: 12)
    }

    func outlineView(
        _ outlineView: NSOutlineView,
        shouldSelectItem item: Any
    ) -> Bool {
        guard let item = item as? ContainerListNode else { return false }
        switch item.presentation {
        case .section:
            return false
        case .compose:
            if outlineView.isItemExpanded(item) {
                outlineView.collapseItem(item)
            } else {
                outlineView.expandItem(item)
            }
            return false
        case .container:
            return true
        }
    }

    func outlineViewSelectionDidChange(_: Notification) {
        guard !isApplyingSelection else { return }
        let selectedID = container(at: outlineView.selectedRow)?.id
        guard selectedID != viewModel.selectedID else { return }
        if selectedID == nil,
            let currentID = viewModel.selectedID,
            let currentNode = node(forContainerID: currentID),
            outlineView.row(forItem: currentNode) == -1
        {
            return
        }
        viewModel.selectedID = selectedID
        if let selectedID {
            actions.select(selectedID)
        }
    }

    func outlineViewItemDidExpand(_ notification: Notification) {
        updateExpansion(from: notification, expanded: true)
    }

    func outlineViewItemDidCollapse(_ notification: Notification) {
        updateExpansion(from: notification, expanded: false)
    }

    func menuNeedsUpdate(_: NSMenu) {
        let clickedRow = outlineView.clickedRow
        contextContainerID = container(at: clickedRow)?.id
        if contextContainerID != nil, outlineView.selectedRow != clickedRow {
            outlineView.selectRowIndexes(
                IndexSet(integer: clickedRow),
                byExtendingSelection: false
            )
        }

        let container = contextContainerID.flatMap(currentContainer)
        contextToggleItem?.title =
            container?.isRunning == true ? "Stop" : "Start"
        contextToggleItem?.isEnabled = container?.isTransitioning == false
        contextCopyNameItem?.isEnabled = container != nil
        contextCopyIDItem?.isEnabled = container != nil
        contextDeleteItem?.isEnabled = container != nil
    }

    private func observeAndRender() {
        let snapshot = withObservationTracking {
            ContainerListSnapshot(viewModel: viewModel)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeAndRender()
            }
        }
        render(snapshot)
    }

    private func render(_ snapshot: ContainerListSnapshot) {
        let previous = self.snapshot
        let rootsChanged = previous?.roots != snapshot.roots
        let expansionChanged =
            previous?.expandedGroups != snapshot.expandedGroups
        let presentationChanged =
            previous == nil
            || previous?.loadState != snapshot.loadState
            || previous?.hasContainers != snapshot.hasContainers
            || (snapshot.roots.isEmpty && previous?.searchText != snapshot.searchText)

        self.snapshot = snapshot
        if rootsChanged {
            if tree.isEmpty {
                // An empty outline has no rows, expansion, or selection to keep,
                // so a fresh load is the diff with nothing left to preserve.
                tree.replace(with: snapshot.roots)
                reloadOutline(expandedGroups: snapshot.expandedGroups)
            } else {
                applyIncrementalUpdate(
                    to: snapshot.roots,
                    expandedGroups: snapshot.expandedGroups
                )
            }
        }
        // Checked independently of `rootsChanged`: a load publishes new
        // containers and then `applyExpandedGroups` in the same turn, and the
        // incremental path above re-applies expansion only to groups it moved.
        if expansionChanged {
            applyExpansion(snapshot.expandedGroups, to: tree.roots)
        }

        if rootsChanged || presentationChanged {
            switch snapshot.loadState {
            case .waiting, .loading:
                showPlaceholder(.loading(title: loadingTitle))
            case .failed(let message):
                showPlaceholder(
                    .error(title: "Failed to load containers", message: message),
                    action: .init(title: "Retry", handler: actions.retry)
                )
            case .loaded where !snapshot.hasContainers:
                placeholderView.isHidden = true
                scrollView.isHidden = true
                emptyStateView.isHidden = false
            case .loaded where snapshot.roots.isEmpty:
                showPlaceholder(
                    .empty(
                        systemImage: "magnifyingglass",
                        title: "No Results",
                        message: "No containers match “\(snapshot.searchText)”."
                    )
                )
            case .loaded:
                placeholderView.isHidden = true
                emptyStateView.isHidden = true
                scrollView.isHidden = false
            }
            NSAccessibility.post(element: view, notification: .layoutChanged)
        }

        if case .loaded = snapshot.loadState {
            applySelection(snapshot.selectedID)
        }
        #if DEBUG
            renderCount += 1
            renderObserver?()
        #endif
    }

    private func showPlaceholder(
        _ state: StatePlaceholderView.State,
        action: StatePlaceholderView.Action? = nil
    ) {
        placeholderView.update(state, action: action)
        placeholderView.isHidden = false
        emptyStateView.isHidden = true
        scrollView.isHidden = true
    }

    private func setUpOutlineView() {
        let column = NSTableColumn(
            identifier: NSUserInterfaceItemIdentifier("ContainerColumn")
        )
        column.resizingMask = .autoresizingMask
        outlineView.addTableColumn(column)
        outlineView.outlineTableColumn = column
        outlineView.headerView = nil
        outlineView.style = .fullWidth
        outlineView.intercellSpacing = .zero
        outlineView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        outlineView.floatsGroupRows = false
        outlineView.indentationPerLevel = 28
        outlineView.allowsMultipleSelection = false
        outlineView.allowsEmptySelection = true
        outlineView.selectionHighlightStyle = .none
        outlineView.dataSource = self
        outlineView.delegate = self
        outlineView.setAccessibilityLabel("Containers")
        outlineView.menu = makeContextMenu()

        scrollView.documentView = outlineView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
    }
}

extension ContainersListViewController {
    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self

        let toggleItem = menu.addItem(
            withTitle: "Start",
            action: #selector(toggleContextContainer),
            keyEquivalent: ""
        )
        toggleItem.target = self
        contextToggleItem = toggleItem
        menu.addItem(.separator())

        let copyNameItem = menu.addItem(
            withTitle: "Copy Name",
            action: #selector(copyContextContainerName),
            keyEquivalent: ""
        )
        copyNameItem.target = self
        contextCopyNameItem = copyNameItem

        let copyIDItem = menu.addItem(
            withTitle: "Copy ID",
            action: #selector(copyContextContainerID),
            keyEquivalent: ""
        )
        copyIDItem.target = self
        contextCopyIDItem = copyIDItem
        menu.addItem(.separator())

        let deleteItem = menu.addItem(
            withTitle: "Delete",
            action: #selector(deleteContextContainer),
            keyEquivalent: ""
        )
        deleteItem.target = self
        deleteItem.image = NSImage(
            systemSymbolName: "trash",
            accessibilityDescription: nil
        )
        contextDeleteItem = deleteItem
        return menu
    }

    private func dequeueCell(
        for presentation: ContainerListNodePresentation
    ) -> NSTableCellView {
        switch presentation {
        case .section:
            return outlineView.makeView(
                withIdentifier: Self.sectionCellIdentifier,
                owner: nil
            ) as? NSTableCellView ?? makeSectionCell()
        case .compose:
            let cell =
                outlineView.makeView(
                    withIdentifier: Self.composeCellIdentifier,
                    owner: nil
                ) as? ContainerGroupTableCellView ?? ContainerGroupTableCellView()
            cell.identifier = Self.composeCellIdentifier
            return cell
        case .container:
            let cell =
                outlineView.makeView(
                    withIdentifier: Self.containerCellIdentifier,
                    owner: nil
                ) as? ContainerTableCellView ?? ContainerTableCellView()
            cell.identifier = Self.containerCellIdentifier
            return cell
        }
    }

    private func configure(
        _ cell: NSTableCellView,
        for presentation: ContainerListNodePresentation
    ) {
        switch presentation {
        case .section(let title):
            cell.textField?.stringValue = title
            cell.setAccessibilityLabel(title)
        case .compose(let project, let containers):
            guard let cell = cell as? ContainerGroupTableCellView else { return }
            configureComposeCell(
                cell,
                project: project,
                containers: containers.map(\.container)
            )
        case .container(let container):
            guard let cell = cell as? ContainerTableCellView else { return }
            configureContainerCell(cell, container: container.container)
        }
    }

    private func makeSectionCell() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = Self.sectionCellIdentifier
        cell.setAccessibilityElement(true)
        cell.setAccessibilityRole(.group)

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 12),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
            label.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -4),
        ])
        return cell
    }

    private func configureComposeCell(
        _ cell: ContainerGroupTableCellView,
        project: String,
        containers: [ContainerViewModel]
    ) {
        let ids = containers.map(\.id)
        cell.configure(
            project: project,
            containers: containers,
            isExpanded: viewModel.isGroupExpanded(project),
            onToggle: { [weak self] in
                self?.toggleGroup(project: project, expectedIDs: ids)
            },
            onDelete: { [weak self] in
                self?.confirmDeleteGroup(project: project, expectedIDs: ids)
            }
        )
    }

    private func configureContainerCell(
        _ cell: ContainerTableCellView,
        container: ContainerViewModel
    ) {
        cell.configure(
            container: container,
            useDNS: useDNS,
            onOpenPort: { [weak self] port in
                self?.openPort(port, containerID: container.id)
            },
            onToggle: { [weak self] in
                self?.toggleContainer(container.id)
            },
            onDelete: { [weak self] in
                self?.confirmDeleteContainer(container.id)
            }
        )
    }

    private func reloadOutline(expandedGroups: Set<String>) {
        applyingSelection {
            applyingExpansion {
                outlineView.reloadData()
            }
        }
        applyExpansion(expandedGroups, to: tree.roots)
    }

    /// Edits the outline row by row instead of reloading it, so rows that did
    /// not change keep their views, expansion, and selection.
    private func applyIncrementalUpdate(
        to roots: [ContainerListNodePresentation],
        expandedGroups: Set<String>
    ) {
        let update = tree.update(to: roots)
        if !update.steps.isEmpty {
            applyingSelection {
                applyingExpansion {
                    outlineView.beginUpdates()
                    for step in update.steps {
                        apply(step)
                    }
                    outlineView.endUpdates()
                }
            }
        }
        applyExpansion(expandedGroups, to: update.repositionedGroups)
        for node in update.reconfigured {
            reconfigureVisibleCell(for: node)
        }
    }

    private func apply(_ step: ContainerListTree.Step) {
        switch step {
        case .remove(let parent, let index):
            outlineView.removeItems(
                at: IndexSet(integer: index),
                inParent: parent,
                withAnimation: []
            )
        case .insert(let parent, let index, _):
            outlineView.insertItems(
                at: IndexSet(integer: index),
                inParent: parent,
                withAnimation: []
            )
        case .move(let parent, let from, let to):
            outlineView.moveItem(at: from, inParent: parent, to: to, inParent: parent)
        }
    }

    private func reconfigureVisibleCell(for node: ContainerListNode) {
        let row = outlineView.row(forItem: node)
        guard
            row >= 0,
            let cell = outlineView.view(
                atColumn: 0,
                row: row,
                makeIfNecessary: false
            ) as? NSTableCellView
        else {
            return
        }
        configure(cell, for: node.presentation)
    }

    private func reconfigureVisibleContainerCells() {
        for row in 0..<outlineView.numberOfRows {
            guard
                let node = outlineView.item(atRow: row) as? ContainerListNode,
                case .container = node.presentation
            else {
                continue
            }
            reconfigureVisibleCell(for: node)
        }
    }

    private func applyExpansion(
        _ expandedGroups: Set<String>,
        to nodes: [ContainerListNode]
    ) {
        applyingExpansion {
            for node in nodes {
                guard case .compose(let project, _) = node.presentation else {
                    continue
                }
                if expandedGroups.contains(project) {
                    outlineView.expandItem(node)
                } else {
                    outlineView.collapseItem(node)
                }
            }
        }
    }

    private func updateExpansion(
        from notification: Notification,
        expanded: Bool
    ) {
        guard
            let node = notification.userInfo?["NSObject"] as? ContainerListNode,
            case .compose(let project, _) = node.presentation
        else {
            return
        }
        let row = outlineView.row(forItem: node)
        if row >= 0 {
            (outlineView.view(
                atColumn: 0,
                row: row,
                makeIfNecessary: false
            ) as? ContainerGroupTableCellView)?.setExpanded(expanded)
        }
        guard
            !isApplyingExpansion,
            viewModel.expandedGroups.contains(project) != expanded
        else {
            return
        }
        viewModel.toggleGroup(project)
    }

    private func applySelection(_ selectedID: String?) {
        guard
            let selectedID,
            let node = node(forContainerID: selectedID),
            outlineView.row(forItem: node) >= 0
        else {
            if let selectedID,
                !viewModel.containers.contains(where: { $0.id == selectedID })
            {
                viewModel.selectedID = nil
            }
            guard outlineView.selectedRow != -1 else { return }
            applyingSelection {
                outlineView.deselectAll(nil)
            }
            return
        }

        let row = outlineView.row(forItem: node)
        guard outlineView.selectedRow != row else { return }
        applyingSelection {
            outlineView.selectRowIndexes(
                IndexSet(integer: row),
                byExtendingSelection: false
            )
        }
        outlineView.scrollRowToVisible(row)
    }

    private func applyingSelection(_ action: () -> Void) {
        isApplyingSelection = true
        defer { isApplyingSelection = false }
        action()
    }

    private func applyingExpansion(_ action: () -> Void) {
        isApplyingExpansion = true
        defer { isApplyingExpansion = false }
        action()
    }

    private func node(forContainerID id: String) -> ContainerListNode? {
        tree.node(for: .container(id))
    }

    private func container(at row: Int) -> ContainerViewModel? {
        guard
            row >= 0,
            let node = outlineView.item(atRow: row) as? ContainerListNode,
            case .container(let container) = node.presentation
        else {
            return nil
        }
        return container.container
    }

    private func currentContainer(_ id: String) -> ContainerViewModel? {
        viewModel.containers.first { $0.id == id }
    }

    private func currentVisibleGroup(
        project: String,
        expectedIDs: [String]
    ) -> [ContainerViewModel]? {
        guard
            let containers = viewModel.composeGroups.first(where: {
                $0.project == project
            })?.containers,
            Set(containers.map(\.id)) == Set(expectedIDs)
        else {
            return nil
        }
        return containers
    }

    private func toggleContainer(_ id: String) {
        guard let container = currentContainer(id), !container.isTransitioning else {
            return
        }
        actions.toggle(id)
    }

    private func toggleGroup(project: String, expectedIDs: [String]) {
        guard
            let containers = currentVisibleGroup(
                project: project,
                expectedIDs: expectedIDs
            ),
            !containers.contains(where: \.isTransitioning)
        else {
            return
        }
        actions.toggleGroup(project, expectedIDs)
    }

    private func openPort(_ port: PortMapping, containerID: String) {
        guard
            let container = currentContainer(containerID),
            container.ports.contains(port),
            useDNS || port.hostPort > 0,
            let url = container.portURL(port, useDNS: useDNS)
        else {
            return
        }
        NSWorkspace.shared.open(url)
    }

    private func confirmDeleteContainer(_ id: String) {
        guard
            let container = currentContainer(id),
            deleteAlert == nil,
            let window = view.window
        else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Delete Container"
        alert.informativeText =
            "Are you sure you want to delete “\(container.name)”? This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        deleteAlert = alert
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            deleteAlert = nil
            guard
                response == .alertFirstButtonReturn,
                currentContainer(id) != nil
            else {
                return
            }
            actions.delete(id)
        }
    }

    private func confirmDeleteGroup(
        project: String,
        expectedIDs: [String]
    ) {
        guard
            let containers = currentVisibleGroup(
                project: project,
                expectedIDs: expectedIDs
            ),
            deleteAlert == nil,
            let window = view.window
        else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Delete All Containers"
        alert.informativeText =
            "Are you sure you want to delete all \(containers.count) containers in “\(project)”? This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(
            withTitle: "Delete All (\(containers.count))"
        ).hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        deleteAlert = alert
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            deleteAlert = nil
            guard
                response == .alertFirstButtonReturn,
                currentVisibleGroup(
                    project: project,
                    expectedIDs: expectedIDs
                ) != nil
            else {
                return
            }
            actions.deleteGroup(project, expectedIDs)
        }
    }

    @objc private func toggleContextContainer() {
        guard let contextContainerID else { return }
        toggleContainer(contextContainerID)
    }

    @objc private func copyContextContainerName() {
        guard let container = contextContainerID.flatMap(currentContainer) else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(container.name, forType: .string)
    }

    @objc private func copyContextContainerID() {
        guard let contextContainerID, currentContainer(contextContainerID) != nil else {
            return
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(contextContainerID, forType: .string)
    }

    @objc private func deleteContextContainer() {
        guard let contextContainerID else { return }
        confirmDeleteContainer(contextContainerID)
    }
}
