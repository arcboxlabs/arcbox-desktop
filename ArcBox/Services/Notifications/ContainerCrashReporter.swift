import DockerClient
import Foundation

/// Turns container deaths into at most one notification per batch window.
///
/// A failing `compose up` brings several containers down at once, and one
/// banner per container is unusable. The first crash opens a window, every
/// crash inside it joins the same digest, and the window always fires — a
/// sliding window would let a crash loop defer the report forever.
@MainActor
final class ContainerCrashReporter {
    static let batchWindow: Duration = .seconds(3)

    private var rules = ContainerNotificationRules()
    private var pending: [ContainerCrash] = []
    private var flushTask: Task<Void, Never>?
    private let post: (AppNotification) -> Void

    init(post: @escaping (AppNotification) -> Void) {
        self.post = post
    }

    func handle(_ event: DockerClient.DockerEvent) {
        guard let crash = rules.crash(for: event) else { return }
        pending.append(crash)

        guard flushTask == nil else { return }
        flushTask = Task { [weak self] in
            try? await Task.sleep(for: Self.batchWindow)
            guard !Task.isCancelled else { return }
            self?.flush()
        }
    }

    /// Drop anything in flight. The daemon going away is already its own
    /// notification; the containers it took with it are not news.
    func stop() {
        flushTask?.cancel()
        flushTask = nil
        pending = []
    }

    private func flush() {
        let crashes = pending
        pending = []
        flushTask = nil
        guard let notification = ContainerCrashDigest.notification(for: crashes) else { return }
        post(notification)
    }
}
