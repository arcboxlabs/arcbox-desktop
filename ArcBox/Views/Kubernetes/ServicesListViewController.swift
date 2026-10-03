import AppKit
import Observation

@MainActor
final class ServicesListViewController: NSViewController,
    NSTableViewDataSource,
    NSTableViewDelegate,
    NSMenuDelegate
{
    private struct Snapshot: Equatable {
        let lifecycle: KubernetesLifecycle
        let streamPhase: KubernetesStreamPhase
        let hasServices: Bool
        let rows: [ServiceViewModel]
        let searchText: String
        let selectedID: String?
        let canControl: Bool

        init(
            state: KubernetesState,
            viewModel: ServicesViewModel,
            canControl: Bool
        ) {
            lifecycle = state.lifecycle
            streamPhase = viewModel.streamPhase
            hasServices = !viewModel.services.isEmpty
            rows = viewModel.filteredServices
            searchText = viewModel.searchText
            selectedID = viewModel.selectedID
            self.canControl = canControl
        }
    }

    private static let cellIdentifier = NSUserInterfaceItemIdentifier("ServiceCell")

    private let state: KubernetesState
    private let viewModel: ServicesViewModel
    private let scrollView = NSScrollView()
    private let tableView = NSTableView()
    private let contentStack = NSStackView()
    private let statusBar = NSView()
    private let statusIndicator = NSProgressIndicator()
    private let statusLabel = NSTextField(labelWithString: "")
    private let placeholderView = StatePlaceholderView(
        state: .loading(title: "Checking Kubernetes…")
    )
    private let kubernetesDisabledView = KubernetesDisabledView()
    private let emptyLabel = NSTextField(labelWithString: "")

    private var snapshot: Snapshot?
    private var canControl: Bool
    private var onCheckStatus: @MainActor () -> Void
    private var onStart: @MainActor () -> Void
    private var onStop: @MainActor () -> Void
    private var onRetryStreams: @MainActor () -> Void
    private var contextService: ServiceViewModel?
    private var isApplyingSelection = false

    init(
        state: KubernetesState,
        viewModel: ServicesViewModel,
        canControl: Bool,
        onCheckStatus: @escaping @MainActor () -> Void,
        onStart: @escaping @MainActor () -> Void,
        onStop: @escaping @MainActor () -> Void,
        onRetryStreams: @escaping @MainActor () -> Void
    ) {
        self.state = state
        self.viewModel = viewModel
        self.canControl = canControl
        self.onCheckStatus = onCheckStatus
        self.onStart = onStart
        self.onStop = onStop
        self.onRetryStreams = onRetryStreams
        super.init(nibName: nil, bundle: nil)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    override func loadView() {
        let container = NSView()
        setUpTableView()
        setUpStatusBar()

        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 0
        contentStack.addArrangedSubview(statusBar)
        contentStack.addArrangedSubview(scrollView)
        contentStack.translatesAutoresizingMaskIntoConstraints = false
        placeholderView.translatesAutoresizingMaskIntoConstraints = false
        kubernetesDisabledView.translatesAutoresizingMaskIntoConstraints = false

        emptyLabel.alignment = .center
        emptyLabel.font = .systemFont(ofSize: 13)
        emptyLabel.textColor = .secondaryLabelColor
        emptyLabel.translatesAutoresizingMaskIntoConstraints = false

        container.addSubview(contentStack)
        container.addSubview(placeholderView)
        container.addSubview(kubernetesDisabledView)
        container.addSubview(emptyLabel)
        NSLayoutConstraint.activate([
            contentStack.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            contentStack.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            contentStack.topAnchor.constraint(equalTo: container.topAnchor),
            contentStack.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            statusBar.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            scrollView.widthAnchor.constraint(equalTo: contentStack.widthAnchor),
            placeholderView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            placeholderView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            placeholderView.topAnchor.constraint(equalTo: container.topAnchor),
            placeholderView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            kubernetesDisabledView.leadingAnchor.constraint(equalTo: container.leadingAnchor),
            kubernetesDisabledView.trailingAnchor.constraint(equalTo: container.trailingAnchor),
            kubernetesDisabledView.topAnchor.constraint(equalTo: container.topAnchor),
            kubernetesDisabledView.bottomAnchor.constraint(equalTo: container.bottomAnchor),
            emptyLabel.centerXAnchor.constraint(equalTo: container.centerXAnchor),
            emptyLabel.centerYAnchor.constraint(equalTo: container.centerYAnchor),
            emptyLabel.leadingAnchor.constraint(
                greaterThanOrEqualTo: container.leadingAnchor,
                constant: 16
            ),
            emptyLabel.trailingAnchor.constraint(
                lessThanOrEqualTo: container.trailingAnchor,
                constant: -16
            ),
        ])

        view = container
    }

    override func viewDidLoad() {
        super.viewDidLoad()
        observeAndRender()
    }

    func update(
        canControl: Bool,
        onCheckStatus: @escaping @MainActor () -> Void,
        onStart: @escaping @MainActor () -> Void,
        onStop: @escaping @MainActor () -> Void,
        onRetryStreams: @escaping @MainActor () -> Void
    ) {
        self.canControl = canControl
        self.onCheckStatus = onCheckStatus
        self.onStart = onStart
        self.onStop = onStop
        self.onRetryStreams = onRetryStreams
        guard isViewLoaded else { return }
        render(
            Snapshot(state: state, viewModel: viewModel, canControl: canControl),
            forcePresentation: true
        )
    }

    func numberOfRows(in _: NSTableView) -> Int {
        snapshot?.rows.count ?? 0
    }

    func tableView(
        _: NSTableView,
        viewFor _: NSTableColumn?,
        row: Int
    ) -> NSView? {
        guard let service = service(at: row) else { return nil }
        let cell =
            tableView.makeView(withIdentifier: Self.cellIdentifier, owner: nil)
            as? ServiceTableCellView ?? ServiceTableCellView()
        cell.identifier = Self.cellIdentifier
        cell.configure(service: service)
        return cell
    }

    func tableView(_: NSTableView, heightOfRow _: Int) -> CGFloat {
        AppMetrics.rowHeight
    }

    func tableView(_: NSTableView, rowViewForRow _: Int) -> NSTableRowView? {
        ResourceListRowView(horizontalInset: 8)
    }

    func tableViewSelectionDidChange(_: Notification) {
        guard !isApplyingSelection else { return }
        let selectedID = service(at: tableView.selectedRow)?.id
        guard selectedID != viewModel.selectedID else { return }
        viewModel.selectedID = selectedID
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let clickedRow = tableView.clickedRow
        contextService = service(at: clickedRow)
        if contextService != nil, tableView.selectedRow != clickedRow {
            tableView.selectRowIndexes(
                IndexSet(integer: clickedRow),
                byExtendingSelection: false
            )
        }
        menu.items.forEach { $0.isEnabled = contextService != nil }
    }

    private func observeAndRender() {
        let snapshot = withObservationTracking {
            Snapshot(state: state, viewModel: viewModel, canControl: canControl)
        } onChange: { [weak self] in
            Task { @MainActor [weak self] in
                self?.observeAndRender()
            }
        }
        render(snapshot)
    }

    private func render(
        _ snapshot: Snapshot,
        forcePresentation: Bool = false
    ) {
        let previous = self.snapshot
        let rowsChanged = previous?.rows != snapshot.rows
        let presentationChanged = forcePresentation || previous != snapshot
        self.snapshot = snapshot

        if rowsChanged {
            applyingSelection {
                tableView.reloadData()
            }
        }

        if presentationChanged {
            switch snapshot.lifecycle {
            case .checking:
                showPlaceholder(.loading(title: "Checking Kubernetes…"))
            case .disabled:
                showKubernetesDisabled(
                    .disabled(canControl: snapshot.canControl)
                )
            case .starting:
                showKubernetesDisabled(.starting)
            case .ready:
                renderReady(snapshot)
            case .stopping:
                if snapshot.hasServices {
                    showTable(status: "Stopping Kubernetes…")
                } else {
                    showPlaceholder(.loading(title: "Stopping Kubernetes…"))
                }
            case .failed(let operation, let message):
                showLifecycleFailure(operation, message: message, canControl: snapshot.canControl)
            }
            NSAccessibility.post(element: view, notification: .layoutChanged)
        }

        if snapshot.lifecycle == .ready || snapshot.lifecycle == .stopping {
            applySelection(snapshot.selectedID)
        }
    }

    private func renderReady(_ snapshot: Snapshot) {
        guard snapshot.hasServices else {
            switch snapshot.streamPhase {
            case .connecting:
                showPlaceholder(.loading(title: nil))
            case .live:
                showEmptyText("No services")
            case .reconnecting(let attempt, let lastError):
                showPlaceholder(
                    .error(
                        title: "Unable to load services",
                        message: reconnectMessage(attempt: attempt, lastError: lastError)
                    ),
                    action: snapshot.canControl
                        ? .init(title: "Retry", handler: onRetryStreams)
                        : nil
                )
            }
            return
        }

        guard !snapshot.rows.isEmpty else {
            var message = "No services match “\(snapshot.searchText)”."
            if case .reconnecting(let attempt, let lastError) = snapshot.streamPhase {
                message += "\n\(reconnectMessage(attempt: attempt, lastError: lastError))"
            }
            showPlaceholder(
                .empty(
                    systemImage: "magnifyingglass",
                    title: "No Results",
                    message: message
                )
            )
            return
        }

        switch snapshot.streamPhase {
        case .connecting:
            showTable(status: "Connecting to Kubernetes…")
        case .live:
            showTable()
        case .reconnecting(let attempt, let lastError):
            showTable(status: reconnectMessage(attempt: attempt, lastError: lastError))
        }
    }

    private func showLifecycleFailure(
        _ operation: KubernetesLifecycle.Operation,
        message: String,
        canControl: Bool
    ) {
        switch operation {
        case .status:
            showPlaceholder(
                .error(title: "Unable to check Kubernetes", message: message),
                action: canControl ? .init(title: "Retry", handler: onCheckStatus) : nil
            )
        case .start:
            showKubernetesDisabled(
                .startFailed(message: message, canControl: canControl)
            )
        case .stop:
            showPlaceholder(
                .error(title: "Failed to stop Kubernetes", message: message),
                action: canControl ? .init(title: "Retry", handler: onStop) : nil
            )
        }
    }

    private func reconnectMessage(attempt: Int, lastError: String?) -> String {
        let prefix = "Reconnecting to Kubernetes (attempt \(attempt))"
        guard let lastError else { return prefix }
        return "\(prefix): \(lastError)"
    }

    private func showPlaceholder(
        _ state: StatePlaceholderView.State,
        action: StatePlaceholderView.Action? = nil
    ) {
        statusIndicator.stopAnimation(nil)
        placeholderView.update(state, action: action)
        placeholderView.isHidden = false
        kubernetesDisabledView.isHidden = true
        emptyLabel.isHidden = true
        contentStack.isHidden = true
    }

    private func showKubernetesDisabled(_ state: KubernetesDisabledView.State) {
        statusIndicator.stopAnimation(nil)
        kubernetesDisabledView.update(state, onTurnOn: onStart)
        kubernetesDisabledView.isHidden = false
        placeholderView.isHidden = true
        emptyLabel.isHidden = true
        contentStack.isHidden = true
    }

    private func showEmptyText(_ text: String) {
        statusIndicator.stopAnimation(nil)
        emptyLabel.stringValue = text
        emptyLabel.isHidden = false
        placeholderView.isHidden = true
        kubernetesDisabledView.isHidden = true
        contentStack.isHidden = true
    }

    private func showTable(status: String? = nil) {
        placeholderView.isHidden = true
        kubernetesDisabledView.isHidden = true
        emptyLabel.isHidden = true
        contentStack.isHidden = false
        statusBar.isHidden = status == nil
        statusLabel.stringValue = status ?? ""
        if status == nil {
            statusIndicator.stopAnimation(nil)
        } else {
            statusIndicator.startAnimation(nil)
        }
    }

    private func setUpTableView() {
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("ServiceColumn"))
        column.resizingMask = .autoresizingMask
        tableView.addTableColumn(column)
        tableView.headerView = nil
        tableView.style = .fullWidth
        tableView.intercellSpacing = .zero
        tableView.columnAutoresizingStyle = .lastColumnOnlyAutoresizingStyle
        tableView.allowsMultipleSelection = false
        tableView.allowsEmptySelection = true
        tableView.selectionHighlightStyle = .none
        tableView.dataSource = self
        tableView.delegate = self
        tableView.setAccessibilityLabel("Services")
        tableView.menu = makeContextMenu()

        scrollView.documentView = tableView
        scrollView.drawsBackground = false
        scrollView.hasVerticalScroller = true
        scrollView.autohidesScrollers = true
    }

    private func setUpStatusBar() {
        statusIndicator.style = .spinning
        statusIndicator.controlSize = .small
        statusIndicator.isIndeterminate = true
        statusIndicator.translatesAutoresizingMaskIntoConstraints = false

        statusLabel.font = .systemFont(ofSize: 11)
        statusLabel.textColor = .secondaryLabelColor
        statusLabel.lineBreakMode = .byTruncatingTail
        statusLabel.translatesAutoresizingMaskIntoConstraints = false

        statusBar.addSubview(statusIndicator)
        statusBar.addSubview(statusLabel)
        statusBar.translatesAutoresizingMaskIntoConstraints = false
        NSLayoutConstraint.activate([
            statusBar.heightAnchor.constraint(equalToConstant: 30),
            statusIndicator.leadingAnchor.constraint(equalTo: statusBar.leadingAnchor, constant: 12),
            statusIndicator.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
            statusLabel.leadingAnchor.constraint(equalTo: statusIndicator.trailingAnchor, constant: 8),
            statusLabel.trailingAnchor.constraint(equalTo: statusBar.trailingAnchor, constant: -12),
            statusLabel.centerYAnchor.constraint(equalTo: statusBar.centerYAnchor),
        ])
        statusBar.isHidden = true
    }

    private func makeContextMenu() -> NSMenu {
        let menu = NSMenu()
        menu.autoenablesItems = false
        menu.delegate = self
        menu.addItem(
            withTitle: "Copy Name",
            action: #selector(copyServiceName),
            keyEquivalent: ""
        ).target = self
        return menu
    }

    private func service(at row: Int) -> ServiceViewModel? {
        guard row >= 0, let rows = snapshot?.rows, row < rows.count else { return nil }
        return rows[row]
    }

    private func applySelection(_ selectedID: String?) {
        guard
            let selectedID,
            let rows = snapshot?.rows,
            let row = rows.firstIndex(where: { $0.id == selectedID })
        else {
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

    @objc private func copyServiceName() {
        guard let contextService else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(contextService.name, forType: .string)
    }
}

@MainActor
private final class ServiceTableCellView: NSTableCellView {
    private let iconBox = NSBox()
    private let serviceImageView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let typeLabel = NSTextField(labelWithString: "")

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        iconBox.boxType = .custom
        iconBox.borderWidth = 0
        iconBox.cornerRadius = 6
        iconBox.fillColor = AppColors.iconBackgroundNSColor
        iconBox.translatesAutoresizingMaskIntoConstraints = false

        serviceImageView.image = NSImage(systemSymbolName: "network", accessibilityDescription: nil)
        serviceImageView.symbolConfiguration = .init(pointSize: 14, weight: .regular)
        serviceImageView.contentTintColor = .secondaryLabelColor
        serviceImageView.setAccessibilityElement(false)
        serviceImageView.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(serviceImageView)

        nameLabel.font = .systemFont(ofSize: 13)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        typeLabel.font = .systemFont(ofSize: 11)
        typeLabel.lineBreakMode = .byTruncatingTail
        typeLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let labels = NSStackView(views: [nameLabel, typeLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        labels.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconBox)
        addSubview(labels)
        imageView = serviceImageView
        textField = nameLabel

        NSLayoutConstraint.activate([
            iconBox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconBox.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconBox.widthAnchor.constraint(equalToConstant: AppMetrics.rowIcon),
            iconBox.heightAnchor.constraint(equalToConstant: AppMetrics.rowIcon),
            serviceImageView.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
            serviceImageView.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
            serviceImageView.widthAnchor.constraint(equalToConstant: 20),
            serviceImageView.heightAnchor.constraint(equalToConstant: 20),
            labels.leadingAnchor.constraint(equalTo: iconBox.trailingAnchor, constant: 12),
            labels.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor),
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
            typeLabel.textColor =
                isSelected
                ? .alternateSelectedControlTextColor.withAlphaComponent(0.67)
                : .secondaryLabelColor
            serviceImageView.contentTintColor = .secondaryLabelColor
        }
    }

    func configure(service: ServiceViewModel) {
        nameLabel.stringValue = service.name
        typeLabel.stringValue = service.type.rawValue
        setAccessibilityElement(true)
        setAccessibilityLabel("\(service.name), \(service.type.rawValue)")
    }
}
