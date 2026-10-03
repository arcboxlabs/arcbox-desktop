import AppKit
import Foundation
import Observation

@MainActor
final class ImagesListViewController: NSViewController,
    NSTableViewDataSource,
    NSTableViewDelegate,
    NSMenuDelegate
{
    private enum Row: Equatable {
        case section(String)
        case image(ImageViewModel)
    }

    private struct Snapshot: Equatable {
        let loadState: LoadPhase
        let hasImages: Bool
        let rows: [Row]
        let searchText: String
        let selectedID: String?

        init(viewModel: ImagesViewModel) {
            loadState = viewModel.loadState
            hasImages = !viewModel.images.isEmpty
            searchText = viewModel.searchText
            selectedID = viewModel.selectedID

            let images = viewModel.sortedImages
            let inUse = images.filter(\.inUse)
            let unused = images.filter { !$0.inUse }
            rows =
                (inUse.isEmpty ? [] : [.section("In Use")] + inUse.map(Row.image))
                + (unused.isEmpty ? [] : [.section("Unused")] + unused.map(Row.image))
        }
    }

    private static let sectionCellIdentifier = NSUserInterfaceItemIdentifier("ImageSectionCell")
    private static let imageCellIdentifier = NSUserInterfaceItemIdentifier("ImageCell")

    private let viewModel: ImagesViewModel
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let placeholderView = StatePlaceholderView(
        state: .loading(title: "Loading images…")
    )
    private let emptyStateView = CommandEmptyStateView(
        systemImage: "circle.circle",
        title: "No images yet",
        prompt: "Pull an image:",
        commands: [
            .init(
                command: "docker pull nginx",
                description: "Official nginx image"
            ),
            .init(
                command: "docker pull postgres:16",
                description: "PostgreSQL database"
            ),
            .init(
                command: "docker pull redis:alpine",
                description: "Redis with Alpine Linux"
            ),
        ]
    )

    private var snapshot: Snapshot?
    private var loadingTitle: String
    private var onRetry: @MainActor () -> Void
    private var onDelete: @MainActor (String) -> Void
    private var contextImage: ImageViewModel?
    private var deleteAlert: NSAlert?
    private var isApplyingSelection = false

    init(
        viewModel: ImagesViewModel,
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
                .error(title: "Failed to load images", message: message),
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
        case .image(let image):
            return imageCell(image: image)
        }
    }

    func tableView(_: NSTableView, heightOfRow row: Int) -> CGFloat {
        guard let item = snapshot?.rows[row] else { return 0 }
        switch item {
        case .section: return 28
        case .image: return AppMetrics.rowHeight
        }
    }

    func tableView(_: NSTableView, rowViewForRow row: Int) -> NSTableRowView? {
        guard let item = snapshot?.rows[row] else { return nil }
        if case .image = item {
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
        if case .image = item {
            return true
        }
        return false
    }

    func tableViewSelectionDidChange(_: Notification) {
        guard !isApplyingSelection else { return }
        let selectedID = image(at: tableView.selectedRow)?.id
        guard selectedID != viewModel.selectedID else { return }
        viewModel.selectedID = selectedID
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let clickedRow = tableView.clickedRow
        contextImage = image(at: clickedRow)
        if contextImage != nil, tableView.selectedRow != clickedRow {
            tableView.selectRowIndexes(
                IndexSet(integer: clickedRow),
                byExtendingSelection: false
            )
        }
        let canCopy = contextImage != nil
        menu.item(withTitle: "Copy Name")?.isEnabled = canCopy
        menu.item(withTitle: "Copy ID")?.isEnabled = canCopy
        menu.item(withTitle: "Delete")?.isEnabled = contextImage?.canDelete ?? false
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
            || previous?.hasImages != snapshot.hasImages
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
                    .error(title: "Failed to load images", message: message),
                    action: .init(title: "Retry", handler: onRetry)
                )
            case .loaded where !snapshot.hasImages:
                placeholderView.isHidden = true
                scrollView.isHidden = true
                emptyStateView.isHidden = false
            case .loaded where snapshot.rows.isEmpty:
                showPlaceholder(
                    .empty(
                        systemImage: "magnifyingglass",
                        title: "No Results",
                        message: "No images match “\(snapshot.searchText)”."
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
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ImageColumn"))
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
        tableView.setAccessibilityLabel("Images")
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
            action: #selector(copyImageName),
            keyEquivalent: ""
        ).target = self
        menu.addItem(
            withTitle: "Copy ID",
            action: #selector(copyImageID),
            keyEquivalent: ""
        ).target = self
        menu.addItem(.separator())
        let deleteItem = menu.addItem(
            withTitle: "Delete",
            action: #selector(deleteContextImage),
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

    private func imageCell(image: ImageViewModel) -> ImageTableCellView {
        let cell =
            tableView.makeView(withIdentifier: Self.imageCellIdentifier, owner: nil)
            as? ImageTableCellView ?? ImageTableCellView()
        cell.identifier = Self.imageCellIdentifier
        cell.configure(image: image) { [weak self] in
            self?.confirmDelete(image)
        }
        return cell
    }

    private func image(at row: Int) -> ImageViewModel? {
        guard row >= 0, let rows = snapshot?.rows, row < rows.count else { return nil }
        guard case .image(let image) = rows[row] else { return nil }
        return image
    }

    private func applySelection(_ selectedID: String?) {
        guard
            let selectedID,
            let rows = snapshot?.rows,
            let row = rows.firstIndex(where: {
                guard case .image(let image) = $0 else { return false }
                return image.id == selectedID
            })
        else {
            if let selectedID,
                !viewModel.images.contains(where: { $0.id == selectedID })
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

    @objc private func copyImageName() {
        guard let contextImage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(contextImage.fullName, forType: .string)
    }

    @objc private func copyImageID() {
        guard let contextImage else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(contextImage.dockerId, forType: .string)
    }

    @objc private func deleteContextImage() {
        guard let contextImage else { return }
        confirmDelete(contextImage)
    }

    private func confirmDelete(_ image: ImageViewModel) {
        guard
            image.canDelete,
            viewModel.images.first(where: { $0.id == image.id })?.canDelete == true,
            deleteAlert == nil,
            let window = view.window
        else {
            return
        }

        let alert = NSAlert()
        alert.messageText = "Delete Image?"
        alert.informativeText =
            "Are you sure you want to delete “\(image.fullName)”? This action cannot be undone."
        alert.alertStyle = .warning
        alert.addButton(withTitle: "Delete").hasDestructiveAction = true
        alert.addButton(withTitle: "Cancel")
        deleteAlert = alert
        alert.beginSheetModal(for: window) { [weak self] response in
            guard let self else { return }
            deleteAlert = nil
            guard response == .alertFirstButtonReturn else { return }
            onDelete(image.id)
        }
    }
}

@MainActor
private final class ImageTableCellView: NSTableCellView, ResourceListActionDisplaying {
    private static let palette: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemCyan,
        .systemBlue, .systemPurple, .systemPink, .systemIndigo, .systemTeal,
    ]

    private let iconBox = NSBox()
    private let imageIconView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let architectureBox = NSBox()
    private let architectureLabel = NSTextField(labelWithString: "amd64")
    private let detailLabel = NSTextField(labelWithString: "")
    private let deleteButton = ResourceActionButton()

    private var iconTask: Task<Void, Never>?
    private var representedIconURL: URL?
    private var fallbackColor = NSColor.secondaryLabelColor
    private var showsRemoteIcon = false
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

        imageIconView.imageScaling = .scaleProportionallyDown
        imageIconView.symbolConfiguration = .init(pointSize: 14, weight: .regular)
        imageIconView.setAccessibilityElement(false)
        imageIconView.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(imageIconView)

        nameLabel.font = .systemFont(ofSize: 13)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        architectureBox.boxType = .custom
        architectureBox.borderWidth = 0
        architectureBox.cornerRadius = 4
        architectureBox.fillColor = .quaternarySystemFill
        architectureBox.titlePosition = .noTitle
        architectureBox.contentViewMargins = .zero
        architectureBox.translatesAutoresizingMaskIntoConstraints = false

        architectureLabel.alignment = .center
        architectureLabel.font = .systemFont(ofSize: 10)
        architectureLabel.translatesAutoresizingMaskIntoConstraints = false
        architectureBox.addSubview(architectureLabel)

        let titleRow = NSStackView(views: [nameLabel, architectureBox])
        titleRow.orientation = .horizontal
        titleRow.alignment = .centerY
        titleRow.spacing = 6

        detailLabel.font = .systemFont(ofSize: 11)
        detailLabel.textColor = .secondaryLabelColor
        detailLabel.lineBreakMode = .byTruncatingTail
        detailLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let labels = NSStackView(views: [titleRow, detailLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2

        deleteButton.identifier = NSUserInterfaceItemIdentifier("ImageDeleteButton")
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
        imageView = imageIconView
        textField = nameLabel

        NSLayoutConstraint.activate([
            content.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 24),
            content.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
            content.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconBox.widthAnchor.constraint(equalToConstant: AppMetrics.rowIcon),
            iconBox.heightAnchor.constraint(equalToConstant: AppMetrics.rowIcon),
            imageIconView.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
            imageIconView.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
            imageIconView.widthAnchor.constraint(equalToConstant: 28),
            imageIconView.heightAnchor.constraint(equalToConstant: 28),
            // NSBox consumes 2 points per horizontal edge, leaving 6 points visible.
            architectureLabel.leadingAnchor.constraint(
                equalTo: architectureBox.leadingAnchor,
                constant: 8
            ),
            architectureLabel.trailingAnchor.constraint(
                equalTo: architectureBox.trailingAnchor,
                constant: -8
            ),
            architectureLabel.topAnchor.constraint(equalTo: architectureBox.topAnchor, constant: 2),
            architectureLabel.bottomAnchor.constraint(
                equalTo: architectureBox.bottomAnchor,
                constant: -2
            ),
            deleteButton.widthAnchor.constraint(equalToConstant: AppMetrics.rowActionButton),
            deleteButton.heightAnchor.constraint(equalToConstant: AppMetrics.rowActionButton),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    deinit {
        iconTask?.cancel()
    }

    override func viewWillMove(toSuperview newSuperview: NSView?) {
        super.viewWillMove(toSuperview: newSuperview)
        if newSuperview == nil {
            prepareForReuse()
        }
    }

    override var backgroundStyle: NSView.BackgroundStyle {
        didSet {
            updateColors()
        }
    }

    func configure(
        image: ImageViewModel,
        onDelete: @escaping @MainActor () -> Void
    ) {
        prepareForReuse()

        nameLabel.stringValue = image.fullName
        architectureBox.isHidden = image.architecture != "amd64"
        detailLabel.stringValue = "\(image.sizeDisplay), \(image.createdAgo)"
        canDelete = image.canDelete
        deleteButton.isEnabled = image.canDelete
        deleteButton.toolTip = image.canDelete ? "Delete image" : nil
        deleteButton.setAccessibilityLabel("Delete \(image.fullName)")
        self.onDelete = image.canDelete ? onDelete : nil
        updateActionVisibility()

        fallbackColor = Self.color(for: image.repository)
        showFallbackIcon()
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(
            "\(image.fullName), \(image.sizeDisplay), \(image.inUse ? "In Use" : "Unused")"
        )
        updateColors()

        guard
            let iconURL = image.iconURL,
            !iconURL.isEmpty,
            let url = URL(string: iconURL)
        else {
            return
        }

        representedIconURL = url
        iconTask = Task { [weak self] in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                try Task.checkCancellation()
                guard
                    let downloadedImage = NSImage(data: data),
                    let self,
                    representedIconURL == url
                else {
                    return
                }
                showsRemoteIcon = true
                imageIconView.image = downloadedImage
                imageIconView.contentTintColor = nil
            } catch {
                // Keep the deterministic fallback icon.
            }
        }
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        iconTask?.cancel()
        iconTask = nil
        representedIconURL = nil
        showsRemoteIcon = false
        imageIconView.image = nil
        onDelete = nil
    }

    func setShowsActions(_ showsActions: Bool) {
        self.showsActions = showsActions
        updateActionVisibility()
    }

    private func updateActionVisibility() {
        deleteButton.isHidden = !canDelete || !showsActions
    }

    private static func color(for repository: String) -> NSColor {
        let hash = repository.utf8.reduce(0) { value, byte in
            value &* 31 &+ Int(byte)
        }
        let index = Int(hash.magnitude % UInt(palette.count))
        return palette[index]
    }

    private func showFallbackIcon() {
        showsRemoteIcon = false
        imageIconView.image = NSImage(
            systemSymbolName: "shippingbox",
            accessibilityDescription: nil
        )
        imageIconView.contentTintColor = fallbackColor
    }

    private func updateColors() {
        let isSelected = backgroundStyle == .emphasized
        nameLabel.textColor = isSelected ? .alternateSelectedControlTextColor : .labelColor
        architectureLabel.textColor =
            isSelected ? .alternateSelectedControlTextColor : .labelColor
        architectureBox.fillColor =
            isSelected
            ? .alternateSelectedControlTextColor.withAlphaComponent(0.18)
            : .quaternarySystemFill
        detailLabel.textColor =
            isSelected
            ? .alternateSelectedControlTextColor.withAlphaComponent(0.67)
            : .secondaryLabelColor
        deleteButton.contentTintColor =
            isSelected ? .alternateSelectedControlTextColor : .secondaryLabelColor
        imageIconView.contentTintColor = showsRemoteIcon ? nil : fallbackColor
    }

    @objc private func deletePressed() {
        onDelete?()
    }
}
