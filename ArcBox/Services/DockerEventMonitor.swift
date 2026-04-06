import DockerClient
import Foundation
import OSLog
@preconcurrency import Sentry

// MARK: - Fine-grained Notification Names

extension Notification.Name {
    static let dockerContainerChanged = Notification.Name("dockerContainerChanged")
    static let dockerImageChanged = Notification.Name("dockerImageChanged")
    static let dockerNetworkChanged = Notification.Name("dockerNetworkChanged")
    static let dockerVolumeChanged = Notification.Name("dockerVolumeChanged")
}

// MARK: - DockerEventMonitor

/// App-level Docker event listener that streams `/events` from the daemon,
/// filters by action whitelist, debounces per resource type, and posts
/// fine-grained notifications so each ListView refreshes independently.
@MainActor
@Observable
final class DockerEventMonitor {

    // MARK: Action Whitelists

    private static let containerActions: Set<String> = [
        "start", "stop", "die", "kill", "pause", "unpause",
        "create", "destroy", "rename", "update",
    ]

    /// Container actions that affect other resource types (images, networks, volumes).
    private static let containerCrossResourceActions: Set<String> = [
        "create", "destroy",
    ]

    private static let imageActions: Set<String> = [
        "pull", "push", "delete", "tag", "untag", "import", "load", "save",
    ]

    private static let networkActions: Set<String> = [
        "create", "connect", "disconnect", "destroy", "remove",
    ]

    private static let volumeActions: Set<String> = [
        "create", "destroy", "mount", "unmount",
    ]

    // MARK: State

    private var task: Task<Void, Never>?
    private var isStopped = true

    /// Per-type debounce work items.
    private var debounceWorkItems: [String: DispatchWorkItem] = [:]
    /// Counts events coalesced per debounce window, keyed by resource type.
    private var eventCountsByType: [String: Int] = [:]
    private static let debounceInterval: TimeInterval = 0.3

    // MARK: Lifecycle

    func start(docker: DockerClient) {
        // Idempotent: cancel existing task before starting a new one.
        task?.cancel()
        isStopped = false

        task = Task {
            while !Task.isCancelled, !isStopped {
                do {
                    for try await event in docker.streamEvents() {
                        guard !Task.isCancelled, !isStopped else { break }
                        handleEvent(event)
                    }
                } catch {
                    if Task.isCancelled || isStopped { break }
                    Log.docker.warning(
                        "Event stream error, reconnecting in 2s: \(error.localizedDescription, privacy: .private)")
                }

                guard !Task.isCancelled, !isStopped else { break }
                try? await Task.sleep(for: .seconds(2))
            }
            Log.docker.info("Event monitor stopped")
        }
        Log.docker.info("Event monitor started")
        SentrySDK.addBreadcrumb(
            {
                let b = Breadcrumb(level: .info, category: "docker.events")
                b.message = "Event monitor started"
                return b
            }())
    }

    func stop() {
        isStopped = true
        task?.cancel()
        task = nil
        cancelAllDebounce()
        SentrySDK.addBreadcrumb(
            {
                let b = Breadcrumb(level: .info, category: "docker.events")
                b.message = "Event monitor stopped"
                return b
            }())
    }

    // MARK: Event Dispatch

    /// Visible to tests via @testable import.
    func handleEvent(_ event: DockerClient.DockerEvent) {
        switch event.type {
        case "container":
            guard Self.containerActions.contains(event.action) else { return }
            debouncedPost(.dockerContainerChanged, type: "container")
            if Self.containerCrossResourceActions.contains(event.action) {
                debouncedPost(.dockerDataChanged, type: "container-cross")
            }

        case "image":
            guard Self.imageActions.contains(event.action) else { return }
            debouncedPost(.dockerImageChanged, type: "image")

        case "network":
            guard Self.networkActions.contains(event.action) else { return }
            debouncedPost(.dockerNetworkChanged, type: "network")

        case "volume":
            guard Self.volumeActions.contains(event.action) else { return }
            debouncedPost(.dockerVolumeChanged, type: "volume")

        default:
            break  // Unknown type — silently ignore
        }
    }

    // MARK: Debounce

    private func debouncedPost(_ name: Notification.Name, type: String) {
        eventCountsByType[type, default: 0] += 1
        debounceWorkItems[type]?.cancel()
        let coalescedCount = eventCountsByType[type]!
        let item = DispatchWorkItem { [weak self] in
            NotificationCenter.default.post(name: name, object: nil)
            if coalescedCount > 1 {
                Log.docker.debug(
                    "Debounced \(coalescedCount, privacy: .public) \(type, privacy: .public) events into 1 notification"
                )
            }
            self?.eventCountsByType[type] = 0
        }
        debounceWorkItems[type] = item
        DispatchQueue.main.asyncAfter(
            deadline: .now() + Self.debounceInterval,
            execute: item
        )
    }

    private func cancelAllDebounce() {
        for (_, item) in debounceWorkItems {
            item.cancel()
        }
        debounceWorkItems.removeAll()
    }
}
