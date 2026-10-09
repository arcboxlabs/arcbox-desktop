import AppKit
import SwiftUI

@MainActor
final class StatePlaceholderView: NSHostingView<StatePlaceholderContent> {
    enum State {
        case loading(title: String?)
        case empty(systemImage: String, title: String, message: String?)
        case error(title: String, message: String?)
        case noSelection(systemImage: String, title: String)
        case plain(title: String)
    }

    struct Action {
        let title: String
        let handler: @MainActor () -> Void
    }

    init(state: State, action: Action? = nil) {
        super.init(rootView: StatePlaceholderContent(state: state, action: action))
        sizingOptions = []
        updateAccessibility(for: state)
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }

    @available(*, unavailable)
    required init(rootView: StatePlaceholderContent) {
        fatalError("init(rootView:) has not been implemented")
    }

    func update(_ state: State, action: Action? = nil) {
        rootView = StatePlaceholderContent(state: state, action: action)
        updateAccessibility(for: state)
    }

    private func updateAccessibility(for state: State) {
        setAccessibilityElement(true)
        setAccessibilityRole(.group)
        setAccessibilityLabel(state.title)
        setAccessibilityHelp(state.message)
        // Not read by VoiceOver: it lets a UI test wait for the loading state
        // to end without matching on wording a resource could also carry.
        setAccessibilityIdentifier(state.accessibilityIdentifier)
    }
}

struct StatePlaceholderContent: View {
    let state: StatePlaceholderView.State
    let action: StatePlaceholderView.Action?

    var body: some View {
        Group {
            switch state {
            case .loading(let title):
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.small)
                    if let title {
                        Text(title)
                            .font(.system(size: 13))
                            .foregroundStyle(.secondary)
                    }
                }
                .accessibilityElement(children: .combine)
            case .empty(let systemImage, let title, let message):
                unavailable(
                    systemImage: systemImage,
                    title: title,
                    message: message
                )
            case .error(let title, let message):
                unavailable(
                    systemImage: "exclamationmark.triangle",
                    title: title,
                    message: message
                )
            case .noSelection(let systemImage, let title):
                unavailable(systemImage: systemImage, title: title, message: nil)
            case .plain(let title):
                Text(title)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }

    private func unavailable(
        systemImage: String,
        title: String,
        message: String?
    ) -> some View {
        ContentUnavailableView {
            Label(title, systemImage: systemImage)
        } description: {
            if let message {
                Text(message)
            }
        } actions: {
            if let action {
                Button(action.title, action: action.handler)
            }
        }
    }
}

extension StatePlaceholderView.State {
    fileprivate var title: String? {
        switch self {
        case .loading(let title):
            title
        case .empty(_, let title, _),
            .error(let title, _),
            .noSelection(_, let title),
            .plain(let title):
            title
        }
    }

    fileprivate var message: String? {
        switch self {
        case .empty(_, _, let message), .error(_, let message):
            message
        case .loading, .noSelection, .plain:
            nil
        }
    }

    /// Identifies each placeholder state without relying on its display text.
    fileprivate var accessibilityIdentifier: String {
        switch self {
        case .loading: "placeholder.loading"
        case .empty: "placeholder.empty"
        case .error: "placeholder.error"
        case .noSelection: "placeholder.noSelection"
        case .plain: "placeholder.plain"
        }
    }
}
