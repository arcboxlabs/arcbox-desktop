import AppKit
import Observation

@MainActor
final class NetworksListViewController: NSViewController,
    NSTableViewDataSource,
    NSTableViewDelegate,
    NSMenuDelegate
{
    private enum Row: Equatable {
        case section(String)
        case network(NetworkViewModel)
    }

    private struct Snapshot: Equatable {
        let loadState: LoadPhase
        let hasNetworks: Bool
        let rows: [Row]
        let searchText: String
        let selectedID: String?

        init(viewModel: NetworksViewModel) {
            loadState = viewModel.loadState
            hasNetworks = !viewModel.networks.isEmpty
            searchText = viewModel.searchText
            selectedID = viewModel.selectedID

            let networks = viewModel.sortedNetworks
            let inUse = networks.filter { $0.containerCount > 0 }
            let unused = networks.filter { $0.containerCount == 0 }
            rows =
                (inUse.isEmpty ? [] : [.section("In Use")] + inUse.map(Row.network))
                + (unused.isEmpty ? [] : [.section("Unused")] + unused.map(Row.network))
        }
    }

    private static let sectionCellIdentifier = NSUserInterfaceItemIdentifier("NetworkSectionCell")
    private static let networkCellIdentifier = NSUserInterfaceItemIdentifier("NetworkCell")

    private let viewModel: NetworksViewModel
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let placeholderView = StatePlaceholderView(
        state: .loading(title: "Loading networks…")
    )
    private let emptyStateView = CommandEmptyStateView(
        systemImage: "point.3.filled.connected.trianglepath.dotted",
        title: "No networks yet",
        prompt: "Create a network:",
        commands: [
            .init(
                command: "docker network create mynet",
                description: "Create bridge network"
            ),
            .init(
                command: "docker network create --driver overlay mynet",
                description: "Create overlay network"
            ),
        ]
    )

    private var snapshot: Snapshot?
    private var loadingTitle: String
    private var onRetry: @MainActor () -> Void
    private var onDelete: @MainActor (String) -> Void
    private var contextNetwork: NetworkViewModel?
    private var deleteAlert: NSAlert?
    private var isApplyingSelection = false

    init(
        viewModel: NetworksViewModel,
        loadingTitle: String,
        onRetry: @escaping @MainActor () -> Void,
        onDelete: @escaping @MainActor (String) -> Void
    ) {
        self.viewModel = viewModel
        self.loadingTitle = loadingTitle
        self.onRetry = onRetry
        self.onDelete = onDelete
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView()
        setUpTableView()

        scrollView.translatesAutoresizingMaskIntoConstraints = false
        placeholderView.translatesAutoresizingMaskIntoConstraints = false
        emptyStateView.translatesAutoresizingMaskIntoConstraints = false
        container.addSubview(scrollView)
        container.addSubview(placeholderView)
        container.addSubview(emptyStateView)

        NSLayoutConstraint.activate([
            scrollView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            scrollView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            scrollView.topAnchor.constraint(equalTo: container.topAnchor),
            scrollView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            placeholderView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            placeholderView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            placeholderView.topAnchor.constraint(equalTo: container.topAnchor),
            placeholderView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            emptyStateView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            emptyStateView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            emptyStateView.topAnchor.constraint(equalTo: container.topAnchor),
            emptyStateView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
        ])

        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observeAndRender()
    }

    func update(
        loadingTitle: String,
        onRetry: @escaping @MainActor () -> Void,
        onDelete: @escaping @MainActor (String) -> Void
    ) {
        let loadingTitleChanged = self.loadingTitle != loadingTitle
        self.loadingTitle = loadingTitle
        self.onRetry = onRetry
        self.onDelete = onDelete
        guard let snapshot, isViewLoaded else { return }
        switch snapshot.loadState {
        case .waiting, .loading:
            if loadingTitleChanged {
                placeholderView.update(.loading(title: loadingTitle))
                NSAccessibility.post(element: placeholderView, notification: .layoutChanged)
            }
        case .failed(let message):
            placeholderView.update(
                .error(title: "Failed to load networks", message: message),
                action: .init(title: "Retry", handler: onRetry)
            )
        default:
            break
        }
    }

    func numberOfRows(in _: NSTableView) -> Int {
        snapshot?.rows.count ?? 0
    }

    func tableView(
        _ tableView: NSTableView,
        viewFor _: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard let item = snapshot?.rows[row] else { return nil }
        switch item {
        case .section(let title):
            return sectionCell(title: title)
        case .network(let network):
            return networkCell(network: network)
        }
    }

    func tableView(_: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard let item = snapshot?.rows[row] else { return 0 }
        switch item {
        case .section: return 28
        case .network: return AppMetrics.rowHeight
        }
    }

    func tableView(_: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        guard let item = snapshot?.rows[row] else { return nil }
        if case .network = item {
            return ResourceListRowView(horizontalInset: 12)
        }
        return nil
    }

    func tableView(_: NSTableView, isGroupRow row: Int) -> Bool {
        guard let item = snapshot?.rows[row] else { return false }
        if case .section = item {
            return true
        }
        return false
    }

    func tableView(_: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard let item = snapshot?.rows[row] else { return false }
        if case .network = item {
            return true
        }
        return false
    }

    func tableViewSelectionDidChange(_: Notification) {
        guard !isApplyingSelection else { return }
        let selectedID = network(at: tableView.selectedRow)?.id
        guard selectedID != viewModel.selectedID else { return }
        viewModel.selectedID = selectedID
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let clickedRow = tableView.clickedRow
        contextNetwork = network(at: clickedRow)
        if contextNetwork != nil, tableView.selectedRow != clickedRow {
            tableView.selectRowIndexes(
                IndexSet(integer: clickedRow),
                byExtendingSelection: false
            )
        }

        let canCopy = contextNetwork != nil
        let canDelete = contextNetwork?.canDelete ?? false
        menu.item(withTitle: "Copy Name")?.isEnabled = canCopy
        menu.item(withTitle: "Delete")?.isEnabled = canDelete
        menu.item(withTitle: "Delete")?.isHidden = contextNetwork?.isSystem ?? true
        menu.items.first(where: \.isSeparatorItem)?.isHidden = contextNetwork?.isSystem ?? true
    }

    private func observeAndRender() {
        let snapshot = withObservationTracking {
            Snapshot(viewModel: viewModel)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeAndRender()
            }
        }
        render(snapshot)
    }

    private func render(_ snapshot: Snapshot) {
        let previous = self.snapshot
        let rowsChanged = previous?.rows != snapshot.rows
        let presentationChanged =
            previous == nil
            || previous?.loadState != snapshot.loadState
            || previous?.hasNetworks != snapshot.hasNetworks
            || (snapshot.rows.isEmpty && previous?.searchText != snapshot.searchText)

        self.snapshot = snapshot
        if rowsChanged {
            applyingSelection {
                tableView.reloadData()
            }
        }

        if rowsChanged || presentationChanged {
            switch snapshot.loadState {
            case .waiting, .loading:
                showPlaceholder(.loading(title: loadingTitle))
            case .failed(let message):
                showPlaceholder(
                    .error(title: "Failed to load networks", message: message),
                    action: .init(title: "Retry", handler: onRetry)
                )
            case .loaded where !snapshot.hasNetworks:
                placeholderView.isHidden = true
                scrollView.isHidden = true
                emptyStateView.isHidden = false
            case .loaded where snapshot.rows.isEmpty:
                showPlaceholder(
                    .empty(
                        systemImage: "magnifyingglass",
                        title: "No Results",
                        message: "No networks match “\(snapshot.searchText)”."
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

    private func setUpTableView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("NetworkColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .fullWidth
        tableView.intercellSpacing = .zero
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.floatsGroupRows = false
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.selectionHighlightStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.setAccessibilityLabel("Networks")
        tableView.menu = makeContextMenu()

        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        menu.addItem(
            withTitle: "Copy Name",
            action: #selector(copyNetworkName),
            keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        let deleteItem = menu.addItem(
            withTitle: "Delete",
            action: #selector(deleteContextNetwork),
            keyEquivalent: ""
        )
        deleteItem.target = self
        deleteItem.image = NSImage(systemSymbolName: "trash", accessibilityDescription: nil)
        return menu
    }

    private func sectionCell(title: String) -> NSTableCellView {
        let cell =
            tableView.makeView(withIdentifier: Self.sectionCellIdentifier, owner: nil)
            as? NSTableCellView ?? makeSectionCell()
        cell.textField?.stringValue = title
        return cell
    }

    private func makeSectionCell() -> NSTableCellView {
        let cell = NSTableCellView()
        cell.identifier = Self.sectionCellIdentifier

        let label = NSTextField(labelWithString: "")
        label.font = .systemFont(ofSize: 11, weight: .semibold)
        label.textColor = .secondaryLabelColor
        label.translatesAutoresizingMaskIntoConstraints = false
        cell.addSubview(label)
        cell.textField = label

        NSLayoutConstraint.activate([
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
            label.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -4),
        ])
        return cell
    }

    private func networkCell(network: NetworkViewModel) -> NetworkTableCellView {
        let cell =
            tableView.makeView(withIdentifier: Self.networkCellIdentifier, owner: nil)
            as? NetworkTableCellView ?? NetworkTableCellView()
        cell.identifier = Self.networkCellIdentifier
        cell.configure(network: network) { [weak self] in
            self?.confirmDelete(network)
        }
        return cell
    }

    private func network(at row: Int) -> NetworkViewModel? {
        guard row >= 0, let rows = snapshot?.rows, row < rows.count else { return nil }
        guard case .network(let network) = rows[row] else { return nil }
        return network
    }

    private func applySelection(_ selectedID: String?) {
        guard
            let selectedID,
            let rows = snapshot?.rows,
            let row = rows.firstIndex(where: {
                guard case .network(let network) = $0 else { return false }
                return network.id == selectedID
            })
        else {
            if let selectedID,
                !viewModel.networks.contains(where: { $0.id == selectedID })
            {
                viewModel.selectedID = nil
            }
            guard tableView.selectedRow != -1 else { return }
            applyingSelection {
                tableView.deselectAll(nil)
            }
            return
        }
        guard tableView.selectedRow != row else { return }
        applyingSelection {
            tableView.selectRowIndexes(IndexSet(integer: row), byExtendingSelection: false)
        }
        tableView.scrollRowToVisible(row)
    }

    private func applyingSelection(_ action: () -> Void) {
        isApplyingSelection = true
        defer { isApplyingSelection = false }
        action()
    }

    @objc private func copyNetworkName() {
        guard let contextNetwork else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(contextNetwork.name, forType: .string)
    }

    @objc private func deleteContextNetwork() {
        guard let contextNetwork, contextNetwork.canDelete else { return }
        confirmDelete(contextNetwork)
    }

    private func confirmDelete(_ network: NetworkViewModel) {
        guard
            network.canDelete,
            viewModel.networks.first(where: { $0.id == network.id })?.canDelete == true,
            deleteAlert == nil,
            let window = view.window
        else { return }
        let alert = NSAlert()
        alert.messageText = "Delete Network?"
        alert.informativeText =
            "Are you sure you want to delete network “\(network.name)”? This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        deleteAlert = alert
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            deleteAlert = nil
            guard response == .alertFirstButtonReturn else { return }
            onDelete(network.id)
        }
    }
}

@MainActor
private final class NetworkTableCellView: NSTableCellView, ResourceListActionDisplaying {
    private let iconBox = NSBox()
    private let networkImageView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let driverLabel = NSTextField(labelWithString: "")
    private let deleteButton = ResourceActionButton()
    private var canDelete = false
    private var showsActions = false
    private var onDelete: (@MainActor () -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        iconBox.boxType = .custom
        iconBox.borderWidth = 0
        iconBox.cornerRadius = 6
        iconBox.fillColor = AppColors.iconBackgroundNSColor
        iconBox.translatesAutoresizingMaskIntoConstraints = false

        networkImageView.contentTintColor = .secondaryLabelColor
        networkImageView.symbolConfiguration = .init(pointSize: 14, weight: .regular)
        networkImageView.setAccessibilityElement(false)
        networkImageView.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(networkImageView)

        nameLabel.font = .systemFont(ofSize: 13)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        driverLabel.font = .systemFont(ofSize: 11)
        driverLabel.textColor = .secondaryLabelColor
        driverLabel.lineBreakMode = .byTruncatingTail
        driverLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let labels = NSStackView(views: [nameLabel, driverLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2

        deleteButton.identifier = NSUserInterfaceItemIdentifier("NetworkDeleteButton")
        deleteButton.image = NSImage(systemSymbolName: "trash.fill", accessibilityDescription: nil)
        deleteButton.contentTintColor = .secondaryLabelColor
        deleteButton.isHidden = true
        deleteButton.target = self
        deleteButton.action = #selector(deletePressed)

        let content = NSStackView(views: [iconBox, labels, deleteButton])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.distribution = .fill
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        imageView = networkImageView
        textField = nameLabel

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconBox.widthAnchor.constraint(equalToConstant: AppMetrics.rowIcon),
            iconBox.heightAnchor.constraint(equalToConstant: AppMetrics.rowIcon),
            networkImageView.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
            networkImageView.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
            networkImageView.widthAnchor.constraint(equalToConstant: 16),
            networkImageView.heightAnchor.constraint(equalToConstant: 16),
            deleteButton.widthAnchor.constraint(equalToConstant: AppMetrics.rowActionButton),
            deleteButton.heightAnchor.constraint(equalToConstant: AppMetrics.rowActionButton),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            let isSelected = backgroundStyle == .emphasized
            nameLabel.textColor = isSelected ? .alternateSelectedControlTextColor : .labelColor
            driverLabel.textColor =
                isSelected
                ? .alternateSelectedControlTextColor.withAlphaComponent(0.67)
                : .secondaryLabelColor
            deleteButton.contentTintColor =
                isSelected ? .alternateSelectedControlTextColor : .secondaryLabelColor
        }
    }

    func configure(
        network: NetworkViewModel,
        onDelete: @escaping @MainActor () -> Void
    ) {
        networkImageView.image = NSImage(
            systemSymbolName: network.isSystem ? "globe" : "link",
            accessibilityDescription: nil
        )
        nameLabel.stringValue = network.name
        driverLabel.stringValue = network.driverDisplay
        canDelete = network.canDelete
        deleteButton.isEnabled = network.canDelete
        deleteButton.toolTip = network.canDelete ? "Delete network" : nil
        deleteButton.setAccessibilityLabel("Delete \(network.name)")
        self.onDelete = network.canDelete ? onDelete : nil
        updateActionVisibility()
        setAccessibilityElement(true)
        setAccessibilityLabel(
            "\(network.name), \(network.driverDisplay), \(network.containerCount > 0 ? "In Use" : "Unused")"
        )
    }

    func setShowsActions(_ showsActions: Bool) {
        self.showsActions = showsActions
        updateActionVisibility()
    }

    private func updateActionVisibility() {
        deleteButton.isHidden = !canDelete || !showsActions
    }

    @objc private func deletePressed() {
        onDelete?()
    }
}
