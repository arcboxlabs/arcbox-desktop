import AppKit

@MainActor
final class MachineEmptyStateView: NSView {
    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        let iconBox = NSBox()
        iconBox.identifier = NSUserInterfaceItemIdentifier("MachineEmptyIcon")
        iconBox.boxType = .custom
        iconBox.borderWidth = 0
        iconBox.cornerRadius = 32
        iconBox.fillColor = .quaternarySystemFill
        iconBox.translatesAutoresizingMaskIntoConstraints = false

        let imageView = NSImageView(
            image: NSImage(
                systemSymbolName: "desktopcomputer",
                accessibilityDescription: nil
            ) ?? NSImage()
        )
        imageView.symbolConfiguration = .init(pointSize: 26, weight: .regular)
        imageView.contentTintColor = .tertiaryLabelColor
        imageView.setAccessibilityElement(false)
        imageView.translatesAutoresizingMaskIntoConstraints = false
        iconBox.addSubview(imageView)

        let titleLabel = Self.label("No Linux machines yet")
        titleLabel.font = .systemFont(ofSize: 13)
        titleLabel.alignment = .center

        let promptLabel = Self.label(
            "Create a new machine to run a full Linux environment:"
        )
        let bulletStack = NSStackView(
            views: [
                Self.label("• Ubuntu, Debian, Fedora, and more"),
                Self.label("• Native ARM64 performance on Apple Silicon"),
                Self.label("• Configurable CPU, memory, and disk"),
            ]
        )
        bulletStack.orientation = .vertical
        bulletStack.alignment = .leading
        bulletStack.spacing = 4

        let footerLabel = Self.label(
            "Click \"+\" in the toolbar to get started"
        )
        let contentStack = NSStackView(
            views: [promptLabel, bulletStack, footerLabel]
        )
        contentStack.orientation = .vertical
        contentStack.alignment = .leading
        contentStack.spacing = 12
        contentStack.setCustomSpacing(20, after: bulletStack)
        contentStack.translatesAutoresizingMaskIntoConstraints = false

        let card = NSBox()
        card.identifier = NSUserInterfaceItemIdentifier("MachineEmptyCard")
        card.boxType = .custom
        card.borderWidth = 0
        card.cornerRadius = 10
        card.fillColor = .quaternarySystemFill
        card.translatesAutoresizingMaskIntoConstraints = false
        card.addSubview(contentStack)

        let stack = NSStackView(views: [iconBox, titleLabel, card])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 16
        stack.setAccessibilityElement(true)
        stack.setAccessibilityRole(.group)
        stack.setAccessibilityLabel("No Linux machines yet")
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            iconBox.widthAnchor.constraint(equalToConstant: 64),
            iconBox.heightAnchor.constraint(equalToConstant: 64),
            imageView.centerXAnchor.constraint(equalTo: iconBox.centerXAnchor),
            imageView.centerYAnchor.constraint(equalTo: iconBox.centerYAnchor),
            imageView.widthAnchor.constraint(equalToConstant: 32),
            imageView.heightAnchor.constraint(equalToConstant: 32),
            contentStack.leadingAnchor.constraint(equalTo: card.leadingAnchor, constant: 16),
            contentStack.trailingAnchor.constraint(equalTo: card.trailingAnchor, constant: -16),
            contentStack.topAnchor.constraint(equalTo: card.topAnchor, constant: 16),
            contentStack.bottomAnchor.constraint(equalTo: card.bottomAnchor, constant: -16),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    private static func label(_ text: String) -> NSTextField {
        let label = NSTextField(labelWithString: text)
        label.font = .systemFont(ofSize: 11)
        label.textColor = .secondaryLabelColor
        label.maximumNumberOfLines = 0
        label.lineBreakMode = .byWordWrapping
        label.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
        return label
    }
}

@MainActor
final class MachineLoadErrorView: NSView {
    private let messageLabel = NSTextField(labelWithString: "")
    private let retryButton = NSButton()
    private var onRetry: (@MainActor () -> Void)?

    override init(frame frameRect: NSRect) {
        super.init(frame: frameRect)

        let imageView = NSImageView(
            image: NSImage(
                systemSymbolName: "exclamationmark.triangle",
                accessibilityDescription: nil
            ) ?? NSImage()
        )
        imageView.identifier = NSUserInterfaceItemIdentifier("MachineLoadErrorIcon")
        imageView.symbolConfiguration = .init(pointSize: 32, weight: .regular)
        imageView.contentTintColor = .tertiaryLabelColor
        imageView.setAccessibilityElement(false)
        imageView.translatesAutoresizingMaskIntoConstraints = false

        messageLabel.alignment = .center
        messageLabel.font = .systemFont(ofSize: 13)
        messageLabel.textColor = .secondaryLabelColor
        messageLabel.maximumNumberOfLines = 0
        messageLabel.lineBreakMode = .byWordWrapping

        retryButton.title = "Retry"
        retryButton.bezelStyle = .rounded
        retryButton.controlSize = .regular
        retryButton.target = self
        retryButton.action = #selector(retry)

        let stack = NSStackView(views: [imageView, messageLabel, retryButton])
        stack.orientation = .vertical
        stack.alignment = .centerX
        stack.spacing = 12
        stack.setAccessibilityElement(true)
        stack.setAccessibilityRole(.group)
        stack.translatesAutoresizingMaskIntoConstraints = false
        addSubview(stack)

        NSLayoutConstraint.activate([
            stack.centerXAnchor.constraint(equalTo: centerXAnchor),
            stack.centerYAnchor.constraint(equalTo: centerYAnchor),
            stack.leadingAnchor.constraint(greaterThanOrEqualTo: leadingAnchor, constant: 24),
            stack.trailingAnchor.constraint(lessThanOrEqualTo: trailingAnchor, constant: -24),
            imageView.widthAnchor.constraint(equalToConstant: 32),
            imageView.heightAnchor.constraint(equalToConstant: 32),
            messageLabel.widthAnchor.constraint(lessThanOrEqualToConstant: 420),
        ])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    func update(message: String, onRetry: @escaping @MainActor () -> Void) {
        messageLabel.stringValue = message
        self.onRetry = onRetry
        setAccessibilityLabel(message)
    }

    @objc private func retry() {
        onRetry?()
    }
}
