import AppKit
import OSLog

/// Applies parsed deep links to app navigation.
///
/// URLs can arrive through `NSApplicationDelegate` before the coordinator is
/// configured, so links are buffered until `configure(_:)` provides a target.
final class DeepLinkRouter {
    struct Target {
        let appVM: AppViewModel
        let containersVM: ContainersViewModel
        let volumesVM: VolumesViewModel
        let imagesVM: ImagesViewModel
        let networksVM: NetworksViewModel
        let openMainWindow: () -> Void
        let openSettingsWindow: () -> Void
        /// URL scheme of the OAuth redirect (e.g. `com.arcboxlabs.desktop`).
        /// Callbacks with this scheme are forwarded to `onOAuthCallback` rather
        /// than parsed as `arcbox://` deep links.
        let oauthCallbackScheme: String?
        let onOAuthCallback: (URL) -> Void
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
        guard let target else { return }
        if let scheme = target.oauthCallbackScheme,
            url.scheme?.caseInsensitiveCompare(scheme) == .orderedSame
        {
            Log.deepLink.info("Handling OAuth redirect callback")
            target.onOAuthCallback(url)
            return
        }
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
            if let id {
                select(id, in: item, with: target)
            }
        }
        NSApp.activate()
    }

    /// Item selection is only wired for Docker resources; the other sections'
    /// view models are local to `ContentView` and not reachable from here.
    private func select(_ id: String, in item: NavItem, with target: Target) {
        switch item {
        case .containers: target.containersVM.selectedID = id
        case .volumes: target.volumesVM.selectedID = id
        case .images: target.imagesVM.selectedID = id
        case .networks: target.networksVM.selectedID = id
        case .activity, .pods, .services, .machines, .sandboxes:
            Log.deepLink.info("Item selection unsupported for \(item.rawValue, privacy: .public)")
        }
    }
}
