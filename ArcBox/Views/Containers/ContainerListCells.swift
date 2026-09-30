import AppKit
import Foundation

/// Symbol images and configurations shared by every container row. Resolving
/// an SF Symbol costs a lookup per `NSImage(systemSymbolName:)`, and a list of
/// a few dozen rows did that for each cell it built.
private enum ContainerListSymbols {
    static let group = NSImage(systemSymbolName: "square.3.layers.3d", accessibilityDescription: nil)
    static let container = NSImage(systemSymbolName: "shippingbox", accessibilityDescription: nil)
    static let trash = NSImage(systemSymbolName: "trash.fill", accessibilityDescription: nil)
    static let link = NSImage(systemSymbolName: "link", accessibilityDescription: nil)
    static let play = NSImage(systemSymbolName: "play.fill", accessibilityDescription: nil)
    static let stop = NSImage(systemSymbolName: "stop.fill", accessibilityDescription: nil)
    static let expanded = NSImage(systemSymbolName: "chevron.down", accessibilityDescription: nil)
    static let collapsed = NSImage(systemSymbolName: "chevron.right", accessibilityDescription: nil)

    static let disclosureConfiguration = NSImage.SymbolConfiguration(pointSize: 10, weight: .regular)
    static let groupConfiguration = NSImage.SymbolConfiguration(pointSize: 14, weight: .regular)
    static let containerConfiguration = NSImage.SymbolConfiguration(pointSize: 16, weight: .regular)
}

@MainActor
final class ContainerGroupTableCellView: NSTableCellView, ResourceListActionDisplaying {
    private let disclosureImageView = NSImageView()
    private let iconBox = NSBox()
    private let groupImageView = NSImageView()
    private let projectLabel = NSTextField(labelWithString: "")
    private let countLabel = NSTextField(labelWithString: "")
    private let busyIndicator = NSProgressIndicator()
    private let toggleButton = ResourceActionButton()
    private let deleteButton = ResourceActionButton()
    private let actions = NSStackView()

    private var labelsToActionsConstraint: NSLayoutConstraint?
    private var isBusy = false
    private var showsActions = false
    private var onToggle: (@MainActor () -> Void)?
    private var onDelete: (@MainActor () -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        disclosureImageView.identifier = NSUserInterfaceItemIdentifier(
            "ContainerGroupDisclosureImage"
        )
        disclosureImageView.contentTintColor = .secondaryLabelColor
        disclosureImageView.symbolConfiguration = ContainerListSymbols.disclosureConfiguration
        disclosureImageView.setAccessibilityElement(false)
        disclosureImageView.translatesAutoresizingMaskIntoConstraints = false

        iconBox.boxType = .custom
        iconBox.borderWidth = 0
        iconBox.cornerRadius = 6
        iconBox.fillColor = .quaternarySystemFill
        iconBox.translatesAutoresizingMaskIntoConstraints = false

        groupImageView.image = ContainerListSymbols.group
        groupImageView.symbolConfiguration = ContainerListSymbols.groupConfiguration
        groupImageView.setAccessibilityElement(false)
        groupImageView.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(groupImageView)

        projectLabel.font = .systemFont(ofSize: 13, weight: .medium)
        projectLabel.lineBreakMode = .byTruncatingTail
        projectLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        countLabel.font = .systemFont(ofSize: 11)
        countLabel.textColor = .secondaryLabelColor
        countLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let labels = NSStackView(views: [projectLabel, countLabel])
        labels.orientation = .horizontal
        labels.alignment = .centerY
        labels.spacing = 8
        labels.translatesAutoresizingMaskIntoConstraints = false

        busyIndicator.identifier = NSUserInterfaceItemIdentifier("ContainerGroupBusyIndicator")
        busyIndicator.style = .spinning
        busyIndicator.controlSize = .small
        busyIndicator.isIndeterminate = true
        busyIndicator.translatesAutoresizingMaskIntoConstraints = false

        configureButton(
            toggleButton,
            identifier: "ContainerGroupToggleButton",
            action: #selector(togglePressed)
        )
        configureButton(
            deleteButton,
            identifier: "ContainerGroupDeleteButton",
            action: #selector(deletePressed)
        )
        deleteButton.image = ContainerListSymbols.trash

        // Hidden before they join the stack: hiding an arranged view afterwards
        // makes the stack detach it through KVO, one layout pass per view.
        busyIndicator.isHidden = true
        toggleButton.isHidden = true
        deleteButton.isHidden = true

        actions.setViews([busyIndicator, toggleButton, deleteButton], in: .center)
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 4
        actions.translatesAutoresizingMaskIntoConstraints = false

        setUpLayout(labels: labels)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUpLayout(labels: NSStackView) {
        addSubview(disclosureImageView)
        addSubview(iconBox)
        addSubview(labels)
        addSubview(actions)
        imageView = groupImageView
        textField = projectLabel

        let softWidthConstraints = [
            iconBox.widthAnchor.constraint(equalToConstant: 28),
            toggleButton.widthAnchor.constraint(equalToConstant: AppMetrics.rowActionButton),
            deleteButton.widthAnchor.constraint(equalToConstant: AppMetrics.rowActionButton),
        ]
        softWidthConstraints.forEach { $0.priority = .defaultHigh }

        let labelsToActionsConstraint = labels.trailingAnchor.constraint(
            lessThanOrEqualTo: actions.leadingAnchor,
            constant: -8
        )
        self.labelsToActionsConstraint = labelsToActionsConstraint

        NSLayoutConstraint.activate(
            [
                disclosureImageView.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
                disclosureImageView.centerYAnchor.constraint(equalTo: centerYAnchor),
                disclosureImageView.widthAnchor.constraint(equalToConstant: 14),
                disclosureImageView.heightAnchor.constraint(equalToConstant: 14),
                iconBox.leadingAnchor.constraint(
                    equalTo: disclosureImageView.trailingAnchor,
                    constant: 8
                ),
                iconBox.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconBox.heightAnchor.constraint(equalToConstant: 28),
                groupImageView.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
                groupImageView.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
                groupImageView.widthAnchor.constraint(equalToConstant: 20),
                groupImageView.heightAnchor.constraint(equalToConstant: 20),
                labels.leadingAnchor.constraint(equalTo: iconBox.trailingAnchor, constant: 8),
                labels.centerYAnchor.constraint(equalTo: centerYAnchor),
                labels.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
                actions.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
                actions.centerYAnchor.constraint(equalTo: centerYAnchor),
                busyIndicator.widthAnchor.constraint(equalToConstant: AppMetrics.rowActionButton),
                busyIndicator.heightAnchor.constraint(equalToConstant: AppMetrics.rowActionButton),
                toggleButton.heightAnchor.constraint(equalToConstant: AppMetrics.rowActionButton),
                deleteButton.heightAnchor.constraint(equalToConstant: AppMetrics.rowActionButton),
                labelsToActionsConstraint,
            ] + softWidthConstraints)
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        busyIndicator.stopAnimation(nil)
        onToggle = nil
        onDelete = nil
    }

    func configure(
        project: String,
        containers: [ContainerViewModel],
        isExpanded: Bool,
        onToggle: @escaping @MainActor () -> Void,
        onDelete: @escaping @MainActor () -> Void
    ) {
        prepareForReuse()

        let runningCount = containers.filter(\.isRunning).count
        isBusy = containers.contains(where: \.isTransitioning)
        let hasRunning = runningCount > 0

        setExpanded(isExpanded)
        projectLabel.stringValue = project
        projectLabel.textColor = hasRunning ? .labelColor : .secondaryLabelColor
        countLabel.stringValue = "\(runningCount)/\(containers.count)"
        groupImageView.contentTintColor = hasRunning ? .controlAccentColor : .tertiaryLabelColor
        toggleButton.image = hasRunning ? ContainerListSymbols.stop : ContainerListSymbols.play
        toggleButton.toolTip = hasRunning ? "Stop project containers" : "Start project containers"
        toggleButton.setAccessibilityLabel(
            "\(hasRunning ? "Stop" : "Start") containers in \(project)"
        )
        deleteButton.toolTip = "Delete project containers"
        deleteButton.setAccessibilityLabel(
            "Delete \(containers.count) containers in \(project)"
        )

        toggleButton.isEnabled = !isBusy
        deleteButton.isEnabled = true
        self.onDelete = onDelete
        if isBusy {
            busyIndicator.setAccessibilityLabel("Updating \(project)")
            busyIndicator.startAnimation(nil)
        } else {
            self.onToggle = onToggle
        }
        updateActionVisibility()

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(
            "\(project), \(runningCount) of \(containers.count) running"
        )
    }

    func setShowsActions(_ showsActions: Bool) {
        self.showsActions = showsActions
        updateActionVisibility()
    }

    func setExpanded(_ isExpanded: Bool) {
        disclosureImageView.image =
            isExpanded ? ContainerListSymbols.expanded : ContainerListSymbols.collapsed
    }

    private func configureButton(
        _ button: ResourceActionButton,
        identifier: String,
        action: Selector
    ) {
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func updateActionVisibility() {
        busyIndicator.isHidden = !showsActions || !isBusy
        toggleButton.isHidden = !showsActions || isBusy
        deleteButton.isHidden = !showsActions
        labelsToActionsConstraint?.isActive = showsActions
    }

    @objc private func togglePressed() {
        onToggle?()
    }

    @objc private func deletePressed() {
        onDelete?()
    }
}

@MainActor
final class ContainerTableCellView: NSTableCellView, ResourceListActionDisplaying {
    private static let palette: [NSColor] = [
        .systemRed, .systemOrange, .systemYellow, .systemGreen, .systemCyan,
        .systemBlue, .systemPurple, .systemPink, .systemIndigo, .systemTeal,
    ]

    private let iconBox = NSBox()
    private let containerImageView = NSImageView()
    private let statusDot = NSView()
    private let statusProgressIndicator = NSProgressIndicator()
    private let nameLabel = NSTextField(labelWithString: "")
    private let imageLabel = NSTextField(labelWithString: "")
    private let linkButton = ResourceActionButton()
    private let busyIndicator = NSProgressIndicator()
    private let toggleButton = ResourceActionButton()
    private let deleteButton = ResourceActionButton()
    private let actions = NSStackView()

    private var labelsToActionsConstraint: NSLayoutConstraint?
    private var iconTask: Task<Void, Never>?
    private var representedID: String?
    private var representedIconURL: URL?
    private var fallbackColor = NSColor.secondaryLabelColor
    private var statusColor = NSColor.secondaryLabelColor
    private var showsRemoteIcon = false
    private var ports: [PortMapping] = []
    private var hostDomain = ""
    private var useDNS = false
    private var isBusy = false
    private var showsActions = false
    private var onOpenPort: (@MainActor (PortMapping) -> Void)?
    private var onToggle: (@MainActor () -> Void)?
    private var onDelete: (@MainActor () -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        iconBox.boxType = .custom
        iconBox.borderWidth = 0
        iconBox.cornerRadius = 6
        iconBox.fillColor = AppColors.iconBackgroundNSColor
        iconBox.translatesAutoresizingMaskIntoConstraints = false

        containerImageView.imageScaling = .scaleProportionallyDown
        containerImageView.symbolConfiguration = ContainerListSymbols.containerConfiguration
        containerImageView.setAccessibilityElement(false)
        containerImageView.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(containerImageView)

        statusDot.identifier = NSUserInterfaceItemIdentifier("ContainerStatusDot")
        statusDot.wantsLayer = true
        statusDot.layer?.cornerRadius = 6
        statusDot.setAccessibilityElement(false)
        statusDot.translatesAutoresizingMaskIntoConstraints = false

        statusProgressIndicator.identifier = NSUserInterfaceItemIdentifier(
            "ContainerStatusBusyIndicator"
        )
        statusProgressIndicator.style = .spinning
        statusProgressIndicator.controlSize = .mini
        statusProgressIndicator.isIndeterminate = true
        statusProgressIndicator.isHidden = true
        statusProgressIndicator.setAccessibilityElement(false)
        statusProgressIndicator.translatesAutoresizingMaskIntoConstraints = false

        nameLabel.font = .systemFont(ofSize: 13, weight: .medium)
        nameLabel.lineBreakMode = .byTruncatingTail
        nameLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        imageLabel.font = .systemFont(ofSize: 11)
        imageLabel.textColor = .secondaryLabelColor
        imageLabel.lineBreakMode = .byTruncatingTail
        imageLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let labels = NSStackView(views: [nameLabel, imageLabel])
        labels.orientation = .vertical
        labels.alignment = .leading
        labels.spacing = 2
        labels.translatesAutoresizingMaskIntoConstraints = false

        configureButton(
            linkButton,
            identifier: "ContainerLinkButton",
            action: #selector(linkPressed)
        )
        linkButton.image = ContainerListSymbols.link

        busyIndicator.identifier = NSUserInterfaceItemIdentifier("ContainerBusyIndicator")
        busyIndicator.style = .spinning
        busyIndicator.controlSize = .small
        busyIndicator.isIndeterminate = true
        busyIndicator.translatesAutoresizingMaskIntoConstraints = false

        configureButton(
            toggleButton,
            identifier: "ContainerToggleButton",
            action: #selector(togglePressed)
        )
        configureButton(
            deleteButton,
            identifier: "ContainerDeleteButton",
            action: #selector(deletePressed)
        )
        deleteButton.image = ContainerListSymbols.trash

        // Hidden before they join the stack: hiding an arranged view afterwards
        // makes the stack detach it through KVO, one layout pass per view.
        linkButton.isHidden = true
        busyIndicator.isHidden = true
        toggleButton.isHidden = true
        deleteButton.isHidden = true

        actions.setViews([linkButton, busyIndicator, toggleButton, deleteButton], in: .center)
        actions.orientation = .horizontal
        actions.alignment = .centerY
        actions.spacing = 4
        actions.translatesAutoresizingMaskIntoConstraints = false

        setUpLayout(labels: labels)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private func setUpLayout(labels: NSStackView) {
        addSubview(iconBox)
        addSubview(statusDot)
        addSubview(statusProgressIndicator)
        addSubview(labels)
        addSubview(actions)
        imageView = containerImageView
        textField = nameLabel

        let softWidthConstraints = [
            iconBox.widthAnchor.constraint(equalToConstant: AppMetrics.rowIcon),
            linkButton.widthAnchor.constraint(equalToConstant: AppMetrics.rowActionButton),
            toggleButton.widthAnchor.constraint(equalToConstant: AppMetrics.rowActionButton),
            deleteButton.widthAnchor.constraint(equalToConstant: AppMetrics.rowActionButton),
        ]
        softWidthConstraints.forEach { $0.priority = .defaultHigh }

        let labelsToActionsConstraint = labels.trailingAnchor.constraint(
            lessThanOrEqualTo: actions.leadingAnchor,
            constant: -8
        )
        self.labelsToActionsConstraint = labelsToActionsConstraint

        NSLayoutConstraint.activate(
            [
                iconBox.leadingAnchor.constraint(equalTo: leadingAnchor, constant: 9),
                iconBox.centerYAnchor.constraint(equalTo: centerYAnchor),
                iconBox.heightAnchor.constraint(equalToConstant: AppMetrics.rowIcon),
                containerImageView.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
                containerImageView.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
                containerImageView.widthAnchor.constraint(equalToConstant: 28),
                containerImageView.heightAnchor.constraint(equalToConstant: 28),
                statusDot.widthAnchor.constraint(equalToConstant: 12),
                statusDot.heightAnchor.constraint(equalToConstant: 12),
                statusDot.trailingAnchor.constraint(equalTo: iconBox.trailingAnchor, constant: 2),
                statusDot.bottomAnchor.constraint(equalTo: iconBox.bottomAnchor, constant: 2),
                statusProgressIndicator.widthAnchor.constraint(equalToConstant: 12),
                statusProgressIndicator.heightAnchor.constraint(equalToConstant: 12),
                statusProgressIndicator.trailingAnchor.constraint(
                    equalTo: iconBox.trailingAnchor,
                    constant: 2
                ),
                statusProgressIndicator.bottomAnchor.constraint(
                    equalTo: iconBox.bottomAnchor,
                    constant: 2
                ),
                labels.leadingAnchor.constraint(equalTo: iconBox.trailingAnchor, constant: 8),
                labels.centerYAnchor.constraint(equalTo: centerYAnchor),
                labels.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
                actions.trailingAnchor.constraint(equalTo: trailingAnchor, constant: -24),
                actions.centerYAnchor.constraint(equalTo: centerYAnchor),
                linkButton.heightAnchor.constraint(equalToConstant: AppMetrics.rowActionButton),
                busyIndicator.widthAnchor.constraint(equalToConstant: AppMetrics.rowActionButton),
                busyIndicator.heightAnchor.constraint(equalToConstant: AppMetrics.rowActionButton),
                toggleButton.heightAnchor.constraint(equalToConstant: AppMetrics.rowActionButton),
                deleteButton.heightAnchor.constraint(equalToConstant: AppMetrics.rowActionButton),
                labelsToActionsConstraint,
            ] + softWidthConstraints)
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

    override func viewDidChangeEffectiveAppearance() {
        super.viewDidChangeEffectiveAppearance()
        updateColors()
    }

    override func prepareForReuse() {
        super.prepareForReuse()
        resetIcon()
        representedID = nil
        busyIndicator.stopAnimation(nil)
        statusProgressIndicator.stopAnimation(nil)
        ports = []
        onOpenPort = nil
        onToggle = nil
        onDelete = nil
    }

    /// Fills the cell for `container`. Calling it again for the same container
    /// updates the row in place and keeps a remote icon that is already showing
    /// or loading, so a state flip does not blink the icon back to the fallback.
    func configure(
        container: ContainerViewModel,
        useDNS: Bool,
        onOpenPort: @escaping @MainActor (PortMapping) -> Void,
        onToggle: @escaping @MainActor () -> Void,
        onDelete: @escaping @MainActor () -> Void
    ) {
        let iconURL = Self.iconURL(container.iconURL)
        let keepsIcon = representedID == container.id && representedIconURL == iconURL

        representedID = container.id
        nameLabel.stringValue = container.name
        imageLabel.stringValue = container.image
        fallbackColor =
            !container.isRunning && !container.isTransitioning
            ? .tertiaryLabelColor
            : Self.color(for: container.image)
        statusColor = Self.color(for: container.state)

        self.useDNS = useDNS
        hostDomain = container.connectionHost(useDNS: useDNS)
        ports =
            useDNS
            ? container.ports
            : container.ports.filter { $0.hostPort > 0 }
        linkButton.toolTip = ports.count > 1 ? "Open container port menu" : "Open container port"
        linkButton.setAccessibilityLabel(
            ports.count > 1
                ? "Open \(container.name) port menu"
                : "Open \(container.name) at \(address(for: ports.first))"
        )
        self.onOpenPort = onOpenPort

        toggleButton.image = container.isRunning ? ContainerListSymbols.stop : ContainerListSymbols.play
        toggleButton.toolTip = container.isRunning ? "Stop container" : "Start container"
        toggleButton.setAccessibilityLabel(
            "\(container.isRunning ? "Stop" : "Start") \(container.name)"
        )
        deleteButton.toolTip = "Delete container"
        deleteButton.setAccessibilityLabel("Delete \(container.name)")

        isBusy = container.isTransitioning
        statusDot.isHidden = isBusy
        statusProgressIndicator.isHidden = !isBusy
        toggleButton.isEnabled = !isBusy
        deleteButton.isEnabled = true
        self.onDelete = onDelete
        self.onToggle = isBusy ? nil : onToggle
        if isBusy {
            busyIndicator.setAccessibilityLabel("Updating \(container.name)")
            busyIndicator.startAnimation(nil)
            statusProgressIndicator.startAnimation(nil)
        } else {
            busyIndicator.stopAnimation(nil)
            statusProgressIndicator.stopAnimation(nil)
        }
        updateActionVisibility()

        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(
            "\(container.name), \(container.image), \(container.state.label)"
        )
        if !keepsIcon {
            resetIcon()
            showFallbackIcon()
            loadIcon(iconURL, representedID: container.id)
        }
        updateColors()
    }

    func setShowsActions(_ showsActions: Bool) {
        self.showsActions = showsActions
        updateActionVisibility()
    }

    private func configureButton(
        _ button: ResourceActionButton,
        identifier: String,
        action: Selector
    ) {
        button.identifier = NSUserInterfaceItemIdentifier(identifier)
        button.contentTintColor = .secondaryLabelColor
        button.target = self
        button.action = action
        button.translatesAutoresizingMaskIntoConstraints = false
    }

    private func updateActionVisibility() {
        linkButton.isHidden = !showsActions || ports.isEmpty
        busyIndicator.isHidden = !showsActions || !isBusy
        toggleButton.isHidden = !showsActions || isBusy
        deleteButton.isHidden = !showsActions
        labelsToActionsConstraint?.isActive = showsActions
    }

    private static func iconURL(_ iconURL: String?) -> URL? {
        guard let iconURL, !iconURL.isEmpty else { return nil }
        return URL(string: iconURL)
    }

    private func resetIcon() {
        iconTask?.cancel()
        iconTask = nil
        representedIconURL = nil
        showsRemoteIcon = false
        containerImageView.image = nil
    }

    private func loadIcon(_ url: URL?, representedID: String) {
        guard let url else { return }

        representedIconURL = url
        iconTask = Task { [weak self] in
            do {
                let (data, _) = try await URLSession.shared.data(from: url)
                try Task.checkCancellation()
                guard
                    let image = NSImage(data: data),
                    let self,
                    self.representedID == representedID,
                    representedIconURL == url
                else {
                    return
                }
                showsRemoteIcon = true
                containerImageView.image = image
                containerImageView.contentTintColor = nil
            } catch {
                // Keep the deterministic fallback icon.
            }
        }
    }

    private static func color(for image: String) -> NSColor {
        let hash = image.utf8.reduce(0) { value, byte in
            value &* 31 &+ Int(byte)
        }
        let index = Int(hash.magnitude % UInt(palette.count))
        return palette[index]
    }

    private static func color(for state: ContainerState) -> NSColor {
        switch state {
        case .running: .systemGreen
        case .stopped: .secondaryLabelColor
        case .restarting, .paused: .systemOrange
        case .dead: .systemRed
        }
    }

    private func showFallbackIcon() {
        showsRemoteIcon = false
        containerImageView.image = ContainerListSymbols.container
        containerImageView.contentTintColor = fallbackColor
    }

    private func updateColors() {
        let isSelected = backgroundStyle == .emphasized
        nameLabel.textColor = isSelected ? .alternateSelectedControlTextColor : .labelColor
        imageLabel.textColor =
            isSelected
            ? .alternateSelectedControlTextColor.withAlphaComponent(0.67)
            : .secondaryLabelColor
        linkButton.contentTintColor =
            isSelected ? .alternateSelectedControlTextColor : .secondaryLabelColor
        toggleButton.contentTintColor =
            isSelected ? .alternateSelectedControlTextColor : .secondaryLabelColor
        deleteButton.contentTintColor =
            isSelected ? .alternateSelectedControlTextColor : .secondaryLabelColor
        containerImageView.contentTintColor = showsRemoteIcon ? nil : fallbackColor
        statusDot.layer?.backgroundColor = statusColor.cgColor
        statusDot.layer?.borderWidth = 2
        statusDot.layer?.borderColor =
            (isSelected ? NSColor.controlAccentColor : NSColor.textBackgroundColor).cgColor
    }

    private func address(for port: PortMapping?) -> String {
        guard let port else { return hostDomain }
        let displayPort = useDNS ? port.containerPort : port.hostPort
        return useDNS && displayPort == 80
            ? hostDomain
            : "\(hostDomain):\(displayPort)"
    }

    @objc private func linkPressed() {
        guard !ports.isEmpty else { return }
        guard ports.count > 1 else {
            onOpenPort?(ports[0])
            return
        }

        let menu = NSMenu()
        for (index, port) in ports.enumerated() {
            let item = NSMenuItem(
                title: address(for: port),
                action: #selector(portPressed(_:)),
                keyEquivalent: ""
            )
            item.tag = index
            item.target = self
            menu.addItem(item)
        }
        menu.popUp(
            positioning: nil,
            at: NSPoint(x: linkButton.frame.minX, y: linkButton.frame.minY),
            in: self
        )
    }

    @objc private func portPressed(_ sender: NSMenuItem) {
        guard ports.indices.contains(sender.tag) else { return }
        onOpenPort?(ports[sender.tag])
    }

    @objc private func togglePressed() {
        onToggle?()
    }

    @objc private func deletePressed() {
        onDelete?()
    }
}
