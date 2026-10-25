import AppKit
import OSLog

/// Applies parsed deep links to app navigation.
///
/// URLs can arrive through `NSApplicationDelegate` before the coordinator is
/// configured, so links are buffered until `configure(_:)` provides a target.
final class DeepLinkRouter {
    struct Target {
        let appVM: AppViewModel
        let openMainWindow: () -> Void
        let openSettingsWindow: () -> Void
    }

    private var target: Target?
    private var pending: [URL] = []

    func configure(_ target: Target) {
        self.target = target
        let buffered = pending
        pending = []
        buffered.forEach(dispatch)
    }

    func handle(_ url: URL) {
        if target == nil {
            pending.append(url)
        } else {
            dispatch(url)
        }
    }

    /// Apply a link produced in-process — a notification click — rather than
    /// parsed from an incoming URL. Unlike `handle(_ url:)` this is not
    /// buffered: nothing in-process can produce a link before configuration.
    func handle(_ link: DeepLink) {
        apply(link)
    }

    private func dispatch(_ url: URL) {
        guard let link = DeepLink(url) else {
            Log.deepLink.warning("Ignoring unrecognized deep link: \(url.absoluteString, privacy: .private)")
            return
        }
        Log.deepLink.info("Handling deep link: \(url.absoluteString, privacy: .private)")
        apply(link)
    }

    private func apply(_ link: DeepLink) {
        guard let target else { return }
        switch link {
        case .main:
            target.openMainWindow()
        case .settings:
            target.openSettingsWindow()
        case .section(let item, let id):
            target.openMainWindow()
            target.appVM.navigate(to: item)
            guard let id else {
                target.appVM.clearResourceDeepLink()
                break
            }
            if item == .activity || item == .runner {
                target.appVM.clearResourceDeepLink()
                target.appVM.deepLinkError = "\(item.label) links don’t support resource IDs."
            } else {
                target.appVM.requestResourceDeepLink(section: item, id: id)
            }
        }
        NSApp.activate()
    }
}
