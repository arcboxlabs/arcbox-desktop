import AppKit
import Observation

@MainActor
final class PodsListViewController: NSViewController,
    NSTableViewDataSource,
    NSTableViewDelegate,
    NSMenuDelegate
{
    private struct Snapshot: Equatable {
        let lifecycle: KubernetesLifecycle
        let streamPhase: KubernetesStreamPhase
        let hasPods: Bool
        let rows: [PodViewModel]
        let searchText: String
        let selectedID: String?
        let canControl: Bool

        init(
            state: KubernetesState,
            viewModel: PodsViewModel,
            canControl: Bool
        ) {
            lifecycle = state.lifecycle
            streamPhase = viewModel.streamPhase
            hasPods = !viewModel.pods.isEmpty
            rows = viewModel.filteredPods
            searchText = viewModel.searchText
            selectedID = viewModel.selectedID
            self.canControl = canControl
        }
    }

    private static let cellIdentifier = NSUserInterfaceItemIdentifier("PodCell")

    private let state: KubernetesState
    private let viewModel: PodsViewModel
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
    private var contextPod: PodViewModel?
    private var isApplyingSelection = false

    init(
        state: KubernetesState,
        viewModel: PodsViewModel,
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
        guard let pod = pod(at: row) else { return nil }
        let cell =
            tableView.makeView(withIdentifier: Self.cellIdentifier, owner: nil)
            as? PodTableCellView ?? PodTableCellView()
        cell.identifier = Self.cellIdentifier
        cell.configure(pod: pod)
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
        let selectedID = pod(at: tableView.selectedRow)?.id
        guard selectedID != viewModel.selectedID else { return }
        viewModel.selectedID = selectedID
    }

    func menuNeedsUpdate(_ menu: NSMenu) {
        let clickedRow = tableView.clickedRow
        contextPod = pod(at: clickedRow)
        if contextPod != nil, tableView.selectedRow != clickedRow {
            tableView.selectRowIndexes(
                IndexSet(integer: clickedRow),
                byExtendingSelection: false
            )
        }
        menu.items.forEach { $0.isEnabled = contextPod != nil }
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
                if snapshot.hasPods {
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
        guard snapshot.hasPods else {
            switch snapshot.streamPhase {
            case .connecting:
                showPlaceholder(.loading(title: nil))
            case .live:
                showEmptyText("No pods")
            case .reconnecting(let attempt, let lastError):
                showPlaceholder(
                    .error(
                        title: "Unable to load pods",
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
            var message = "No pods match “\(snapshot.searchText)”."
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
        let column = NSTableColumn(identifier: NSUserInterfaceItemIdentifier("PodColumn"))
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
        tableView.setAccessibilityLabel("Pods")
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
            action: #selector(copyPodName),
            keyEquivalent: ""
        ).target = self
        menu.addItem(
            withTitle: "Copy Namespace",
            action: #selector(copyPodNamespace),
            keyEquivalent: ""
        ).target = self
        return menu
    }

    private func pod(at row: Int) -> PodViewModel? {
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

    @objc private func copyPodName() {
        guard let contextPod else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(contextPod.name, forType: .string)
    }

    @objc private func copyPodNamespace() {
        guard let contextPod else { return }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(contextPod.namespace, forType: .string)
    }
}

@MainActor
final class KubernetesDisabledView: NSView {
    enum State {
        case disabled(canControl: Bool)
        case starting
        case startFailed(message: String, canControl: Bool)
    }

    private let iconView = NSImageView()
    private let titleLabel = NSTextField(labelWithString: "")
    private let errorLabel = NSTextField(labelWithString: "")
    private let progressIndicator = NSProgressIndicator()
    private let actionButton = NSButton()
    private var actionHandler: (@MainActor () -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        iconView.identifier = NSUserInterfaceItemIdentifier("KubernetesDisabledIcon")
        iconView.image = NSImage(systemSymbolName: "gear", accessibilityDescription: nil)
        iconView.imageScaling = .scaleProportionallyDown
        iconView.symbolConfiguration = .init(pointSize: 48, weight: .regular)
        iconView.contentTintColor = .tertiaryLabelColor
        iconView.setAccessibilityElement(false)
        iconView.translatesAutoresizingMaskIntoConstraints = false

        titleLabel.identifier = NSUserInterfaceItemIdentifier("KubernetesDisabledTitle")
        titleLabel.alignment = .center
        titleLabel.font = .systemFont(ofSize: 20, weight: .medium)
        titleLabel.textColor = .secondaryLabelColor

        errorLabel.identifier = NSUserInterfaceItemIdentifier("KubernetesDisabledError")
        errorLabel.alignment = .center
        errorLabel.font = .systemFont(ofSize: 12)
        errorLabel.textColor = .systemRed
        errorLabel.maximumNumberOfLines = 0
        errorLabel.lineBreakMode = .byWordWrapping

        progressIndicator.identifier = NSUserInterfaceItemIdentifier(
            "KubernetesDisabledProgress"
        )
        progressIndicator.style = .spinning
        progressIndicator.controlSize = .regular
        progressIndicator.isIndeterminate = true

        actionButton.identifier = NSUserInterfaceItemIdentifier("KubernetesDisabledAction")
        actionButton.bezelStyle = .rounded
        actionButton.bezelColor = .controlAccentColor
        actionButton.contentTintColor = .white
        actionButton.controlSize = .regular
        actionButton.font = .systemFont(ofSize: 13)
        actionButton.target = self
        actionButton.action = #selector(performAction)

        let stack = NSStackView(
            views: [iconView, titleLabel, errorLabel, progressIndicator, actionButton]
        )
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 20
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            iconView.widthAnchor.constraint(equalToConstant: 48),
            iconView.heightAnchor.constraint(equalToConstant: 48),
            errorLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
        ])

        update(.disabled(canControl: true), onTurnOn: {})
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(_ state: State, onTurnOn: @escaping @MainActor () -> Void) {
        progressIndicator.stopAnimation(nil)
        progressIndicator.isHidden = true
        errorLabel.isHidden = true
        actionButton.isHidden = true
        actionHandler = nil

        switch state {
        case .disabled(let canControl):
            titleLabel.stringValue = "Kubernetes Disabled"
            if canControl {
                actionButton.title = "Turn On"
                actionButton.isHidden = false
                actionHandler = onTurnOn
            } else {
                errorLabel.stringValue = "ArcBox daemon is unavailable."
                errorLabel.isHidden = false
            }
        case .starting:
            titleLabel.stringValue = "Starting Kubernetes…"
            progressIndicator.isHidden = false
            progressIndicator.startAnimation(nil)
        case .startFailed(let message, let canControl):
            titleLabel.stringValue = "Kubernetes Disabled"
            errorLabel.stringValue = message
            errorLabel.isHidden = false
            if canControl {
                actionButton.title = "Retry"
                actionButton.isHidden = false
                actionHandler = onTurnOn
            }
        }

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(titleLabel.stringValue)
        setAccessibilityHelp(errorLabel.isHidden ? nil : errorLabel.stringValue)
    }

    @objc private func performAction() {
        actionHandler?()
    }
}

@MainActor
private final class PodTableCellView: NSTableCellView {
    private let iconBox = NSBox()
    private let podImageView = NSImageView()
    private let nameLabel = NSTextField(labelWithString: "")
    private let namespaceLabel = NSTextField(labelWithString: "")
    private let statusDot = NSView()
    private var statusColor = NSColor.secondaryLabelColor

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        iconBox.boxType = .custom
        iconBox.borderWidth = 0
        iconBox.cornerRadius = 6
        iconBox.fillColor = AppColors.iconBackgroundNSColor
        iconBox.translatesAutoresizingMaskIntoConstraints = false

        podImageView.image = NSImage(systemSymbolName: "cube", accessibilityDescription: nil)
        podImageView.symbolConfiguration = .init(pointSize: 14, weight: .regular)
        podImageView.contentTintColor = .secondaryLabelColor
        podImageView.setAccessibilityElement(false)
        podImageView.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(podImageView)

        nameLabel.font = .systemFont(ofSize: 13)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        namespaceLabel.font = .systemFont(ofSize: 11)
        namespaceLabel.lineBreakMode = .byTruncatingTail
        namespaceLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let labels = NSStackView(views: [nameLabel, namespaceLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        labels.translatesAutoresizingMaskIntoConstraints = false

        statusDot.identifier = NSUserInterfaceItemIdentifier("PodStatusDot")
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = AppMetrics.statusDot / 2
        statusDot.setAccessibilityElement(false)
        statusDot.translatesAutoresizingMaskIntoConstraints = false

        addSubview(iconBox)
        addSubview(labels)
        addSubview(statusDot)
        imageView = podImageView
        textField = nameLabel

        NSLayoutConstraint.activate([
            iconBox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 16),
            iconBox.centerYAnchor.constraint(equalTo: centerYAnchor),
            iconBox.widthAnchor.constraint(equalToConstant: AppMetrics.rowIcon),
            iconBox.heightAnchor.constraint(equalToConstant: AppMetrics.rowIcon),
            podImageView.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
            podImageView.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
            podImageView.widthAnchor.constraint(equalToConstant: 20),
            podImageView.heightAnchor.constraint(equalToConstant: 20),
            labels.leadingAnchor.constraint(equalTo: iconBox.trailingAnchor, constant: 12),
            labels.centerYAnchor.constraint(equalTo: centerYAnchor),
            labels.trailingAnchor.constraint(lessThanOrEqualTo: statusDot.leadingAnchor, constant: -8),
            statusDot.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -16),
            statusDot.centerYAnchor.constraint(equalTo: centerYAnchor),
            statusDot.widthAnchor.constraint(equalToConstant: AppMetrics.statusDot),
            statusDot.heightAnchor.constraint(equalToConstant: AppMetrics.statusDot),
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
            namespaceLabel.textColor =
                isSelected
                ? .alternateSelectedControlTextColor.withAlphaComponent(0.67)
                : .secondaryLabelColor
            podImageView.contentTintColor = .secondaryLabelColor
        }
    }

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        statusDot.layer?.backgroundColor = statusColor.cgColor
    }

    func configure(pod: PodViewModel) {
        nameLabel.stringValue = pod.name
        namespaceLabel.stringValue = pod.namespace
        statusColor = Self.color(for: pod.phase)
        statusDot.layer?.backgroundColor = statusColor.cgColor
        setAccessibilityElement(true)
        setAccessibilityLabel("\(pod.name), \(pod.phase.rawValue)")
    }

    private static func color(for phase: PodPhase) -> NSColor {
        switch phase {
        case .running, .succeeded: .systemGreen
        case .pending: .systemOrange
        case .failed: .systemRed
        case .unknown: .secondaryLabelColor
        }
    }
}
