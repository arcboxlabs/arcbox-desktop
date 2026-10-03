import AppKit
import Observation

@MainActor
final class VolumesListViewController: NSViewController,
    NSTableViewDataSource,
    NSTableViewDelegate,
    NSMenuDelegate
{
    private enum Row: Equatable {
        case section(String)
        case volume(VolumeViewModel)
    }

    private struct Snapshot: Equatable {
        let loadState: LoadPhase
        let hasVolumes: Bool
        let rows: [Row]
        let searchText: String
        let selectedID: String?

        init(viewModel: VolumesViewModel) {
            loadState = viewModel.loadState
            hasVolumes = !viewModel.volumes.isEmpty
            searchText = viewModel.searchText
            selectedID = viewModel.selectedID

            let volumes = viewModel.sortedVolumes
            let inUse = volumes.filter(\.inUse)
            let unused = volumes.filter { !$0.inUse }
            rows =
                (inUse.isEmpty ? [] : [.section("In Use")] + inUse.map(Row.volume))
                + (unused.isEmpty ? [] : [.section("Unused")] + unused.map(Row.volume))
        }
    }

    private static let sectionCellIdentifier = NSUserInterfaceItemIdentifier("VolumeSectionCell")
    private static let volumeCellIdentifier = NSUserInterfaceItemIdentifier("VolumeCell")

    private let viewModel: VolumesViewModel
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let placeholderView = StatePlaceholderView(
        state: .loading(title: "Loading volumes…")
    )
    private let emptyStateView = CommandEmptyStateView(
        systemImage: "internaldrive",
        title: "No volumes yet",
        prompt: "Create a volume:",
        commands: [
            .init(
                command: "docker volume create mydata",
                description: "Create named volume"
            ),
            .init(
                command: "docker run -v mydata:/data nginx",
                description: "Mount volume to container"
            ),
        ]
    )

    private var snapshot: Snapshot?
    private var loadingTitle: String
    private var onRetry: @MainActor () -> Void
    private var onDelete: @MainActor (String) -> Void
    private var contextVolume: VolumeViewModel?
    private var deleteAlert: NSAlert?
    private var isApplyingSelection = false

    init(
        viewModel: VolumesViewModel,
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
                .error(title: "Failed to load volumes", message: message),
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
        case .volume(let volume):
            return volumeCell(volume: volume)
        }
    }

    func tableView(_ tableView: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard let item = snapshot?.rows[row] else { return 0 }
        switch item {
        case .section: return 28
        case .volume: return AppMetrics.rowHeight
        }
    }

    func tableView(_: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        guard let item = snapshot?.rows[row] else { return nil }
        if case .volume = item {
            return ResourceListRowView(horizontalInset: 12)
        }
        return nil
    }

    func tableView(_ tableView: NSTableView, isGroupRow row: Int) -> Bool {
        guard let item = snapshot?.rows[row] else { return false }
        if case .section = item {
            return true
        }
        return false
    }

    func tableView(_ tableView: NSTableView, shouldSelectRow row: Int) -> Bool {
        guard let item = snapshot?.rows[row] else { return false }
        if case .volume = item {
            return true
        }
        return false
    }

    func tableViewSelectionDidChange(_: Notification) {
        guard !isApplyingSelection else { return }
        let selectedID = volume(at: tableView.selectedRow)?.id
        guard selectedID != viewModel.selectedID else { return }
        viewModel.selectedID = selectedID
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let clickedRow = tableView.clickedRow
        contextVolume = volume(at: clickedRow)
        if contextVolume != nil, tableView.selectedRow != clickedRow {
            tableView.selectRowIndexes(
                IndexSet(integer: clickedRow),
                byExtendingSelection: false
            )
        }
        menu.items.forEach { $0.isEnabled = contextVolume != nil }
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
            || previous?.hasVolumes != snapshot.hasVolumes
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
                    .error(title: "Failed to load volumes", message: message),
                    action: .init(title: "Retry", handler: onRetry)
                )
            case .loaded where !snapshot.hasVolumes:
                placeholderView.isHidden = true
                scrollView.isHidden = true
                emptyStateView.isHidden = false
            case .loaded where snapshot.rows.isEmpty:
                showPlaceholder(
                    .empty(
                        systemImage: "magnifyingglass",
                        title: "No Results",
                        message: "No volumes match “\(snapshot.searchText)”."
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
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("VolumeColumn"))
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
        tableView.setAccessibilityLabel("Volumes")
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
            action: #selector(copyVolumeName),
            keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        let deleteItem = menu.addItem(
            withTitle: "Delete",
            action: #selector(deleteContextVolume),
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
        cell.setAccessibilityLabel(title)
        return cell
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
            label.leadingAnchor.constraint(equalTo: cell.leadingAnchor, constant: 16),
            label.trailingAnchor.constraint(equalTo: cell.trailingAnchor, constant: -12),
            label.bottomAnchor.constraint(equalTo: cell.bottomAnchor, constant: -4),
        ])
        return cell
    }

    private func volumeCell(volume: VolumeViewModel) -> VolumeTableCellView {
        let cell =
            tableView.makeView(withIdentifier: Self.volumeCellIdentifier, owner: nil)
            as? VolumeTableCellView ?? VolumeTableCellView()
        cell.identifier = Self.volumeCellIdentifier
        cell.configure(volume: volume) { [weak self] in
            self?.confirmDelete(volume)
        }
        return cell
    }

    private func volume(at row: Int) -> VolumeViewModel? {
        guard row >= 0, let rows = snapshot?.rows, row < rows.count else { return nil }
        guard case .volume(let volume) = rows[row] else { return nil }
        return volume
    }

    private func applySelection(_ selectedID: String?) {
        guard
            let selectedID,
            let rows = snapshot?.rows,
            let row = rows.firstIndex(where: {
                guard case .volume(let volume) = $0 else { return false }
                return volume.id == selectedID
            })
        else {
            if let selectedID,
                !viewModel.volumes.contains(where: { $0.id == selectedID })
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

    @objc private func copyVolumeName() {
        guard let contextVolume else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(contextVolume.name, forType: .string)
    }

    @objc private func deleteContextVolume() {
        guard let contextVolume else { return }
        confirmDelete(contextVolume)
    }

    private func confirmDelete(_ volume: VolumeViewModel) {
        guard deleteAlert == nil, let window = view.window else { return }
        let alert = NSAlert()
        alert.messageText = "Delete Volume?"
        alert.informativeText =
            "Are you sure you want to delete volume “\(volume.name)”? This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        deleteAlert = alert
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            deleteAlert = nil
            guard response == .alertFirstButtonReturn else { return }
            onDelete(volume.name)
        }
    }
}

@MainActor
private final class VolumeTableCellView: NSTableCellView, ResourceListActionDisplaying {
    private let iconBox = NSBox()
    private let volumeImageView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let sizeLabel = NSTextField(labelWithString: "")
    private let deleteButton = ResourceActionButton()
    private var onDelete: (@MainActor () -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        iconBox.boxType = .custom
        iconBox.borderWidth = 0
        iconBox.cornerRadius = 6
        iconBox.fillColor = AppColors.iconBackgroundNSColor
        iconBox.translatesAutoresizingMaskIntoConstraints = false

        volumeImageView.image = NSImage(
            systemSymbolName: "externaldrive",
            accessibilityDescription: nil
        )
        volumeImageView.contentTintColor = .secondaryLabelColor
        volumeImageView.symbolConfiguration = .init(pointSize: 14, weight: .regular)
        volumeImageView.setAccessibilityElement(false)
        volumeImageView.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(volumeImageView)

        nameLabel.font = .systemFont(ofSize: 13)
        nameLabel.lineBreakMode = .byTruncatingTail
        sizeLabel.font = .systemFont(ofSize: 11)
        sizeLabel.textColor = .secondaryLabelColor

        let labels = NSStackView(views: [nameLabel, sizeLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2

        deleteButton.identifier = NSUserInterfaceItemIdentifier("VolumeDeleteButton")
        deleteButton.image = NSImage(systemSymbolName: "trash.fill", accessibilityDescription: nil)
        deleteButton.contentTintColor = .secondaryLabelColor
        deleteButton.isHidden = true
        deleteButton.target = self
        deleteButton.action = #selector(deletePressed)
        deleteButton.toolTip = "Delete volume"
        deleteButton.setAccessibilityLabel("Delete volume")

        let content = NSStackView(views: [iconBox, labels, deleteButton])
        content.orientation = .horizontal
        content.alignment = .centerY
        content.distribution = .fill
        content.spacing = 12
        content.translatesAutoresizingMaskIntoConstraints = false
        addSubview(content)
        imageView = volumeImageView
        textField = nameLabel

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconBox.widthAnchor.constraint(equalToConstant: AppMetrics.rowIcon),
            iconBox.heightAnchor.constraint(equalToConstant: AppMetrics.rowIcon),
            volumeImageView.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
            volumeImageView.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
            volumeImageView.widthAnchor.constraint(equalToConstant: 20),
            volumeImageView.heightAnchor.constraint(equalToConstant: 20),
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
            sizeLabel.textColor =
                isSelected
                ? .alternateSelectedControlTextColor.withAlphaComponent(0.67)
                : .secondaryLabelColor
            deleteButton.contentTintColor =
                isSelected ? .alternateSelectedControlTextColor : .secondaryLabelColor
        }
    }

    func configure(
        volume: VolumeViewModel,
        onDelete: @escaping @MainActor () -> Void
    ) {
        nameLabel.stringValue = volume.name
        sizeLabel.stringValue = volume.sizeDisplay
        self.onDelete = onDelete
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(
            "\(volume.name), \(volume.sizeDisplay), \(volume.inUse ? "In Use" : "Unused")"
        )
        deleteButton.setAccessibilityLabel("Delete \(volume.name)")
    }

    func setShowsActions(_ showsActions: Bool) {
        deleteButton.isHidden = !showsActions
    }

    @objc private func deletePressed() {
        onDelete?()
    }
}
