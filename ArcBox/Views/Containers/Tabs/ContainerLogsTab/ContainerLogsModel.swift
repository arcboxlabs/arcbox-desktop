import AppKit
import DockerClient
import Foundation

/// Streaming state of one container's logs tab.
///
/// The state lives in an observable object instead of `@State` on the tab so
/// that each child view depends only on the properties it reads. A batch of
/// lines then re-evaluates `ContainerLogsContent` alone; `ContainerLogsToolbar`
/// — and the `NSSegmentedControl` behind its stream filter, which re-runs its
/// own view graph on every measurement — stays out of that invalidation scope.
@Observable
final class ContainerLogsModel {
    var logEntries: [LogEntry] = []
    var searchText = ""
    var streamFilter: LogStreamFilter = .all
    var isFollowing = true
    var isLoading = true
    var errorMessage: String?

    @ObservationIgnored private var streamTask: Task<Void, Never>?
    @ObservationIgnored private var docker: DockerClient?
    @ObservationIgnored private var containerID = ""

    let maxLogEntries = 10_000
    /// How long lines may wait to be shown. Long enough to fold a burst into one list
    /// rebuild, short enough to still read as live.
    static let appendInterval = Duration.milliseconds(100)

    var filteredEntries: [LogEntry] {
        var entries = logEntries
        switch streamFilter {
        case .all: break
        case .stdout: entries = entries.filter { $0.stream == .stdout }
        case .stderr: entries = entries.filter { $0.stream == .stderr }
        }
        if !searchText.isEmpty {
            entries = entries.filter {
                $0.message.localizedCaseInsensitiveContains(searchText)
            }
        }
        return entries
    }

    func startStreaming(containerID: String, docker: DockerClient?) async {
        self.containerID = containerID
        self.docker = docker
        cancelStreaming()
        logEntries = []
        isLoading = true
        errorMessage = nil

        guard let docker else {
            errorMessage = "Docker client not available"
            isLoading = false
            return
        }

        // Capture timestamp before history fetch to avoid gaps between phases
        let streamSince = Int(Date().timeIntervalSince1970)

        // Phase 1: Batch-load historical logs (all at once)
        do {
            let historyLines = try await docker.fetchContainerLogs(
                id: containerID,
                tail: 500,
                timestamps: true
            )
            logEntries = historyLines.map(LogEntry.init)
        } catch {
            if !Task.isCancelled {
                errorMessage = error.localizedDescription
            }
        }
        isLoading = false

        if Task.isCancelled { return }

        // Phase 2: Stream only new logs going forward
        guard isFollowing else { return }
        startStreamTask(since: streamSince)
    }

    private func startStreamTask(since: Int? = nil) {
        cancelStreaming()
        streamTask = Task {
            guard let docker else { return }
            let sinceTimestamp = since ?? Int(Date().timeIntervalSince1970)
            let stream = docker.streamContainerLogs(
                id: containerID,
                tail: 0,
                timestamps: true,
                since: sinceTimestamp
            )
            do {
                for try await lines in stream.batched(every: Self.appendInterval) {
                    if Task.isCancelled { break }
                    append(lines)
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                    isFollowing = false
                }
            }
        }
    }

    /// Appends one batch of streamed lines, dropping the oldest past `maxLogEntries`.
    ///
    /// Every line a followed container logs lands here, so this is the path whose
    /// cost the batch regression test pins.
    func append(_ lines: [DockerLogLine]) {
        logEntries.append(contentsOf: lines.map(LogEntry.init))
        if logEntries.count > maxLogEntries {
            logEntries.removeFirst(logEntries.count - maxLogEntries)
        }
    }

    func toggleFollow() {
        isFollowing.toggle()
        if isFollowing {
            startStreamTask()
        } else {
            cancelStreaming()
        }
    }

    func cancelStreaming() {
        streamTask?.cancel()
        streamTask = nil
    }

    func copyLogs() {
        let text = filteredEntries.map { entry in
            if let ts = entry.timestamp {
                return "\(ts) \(entry.message)"
            }
            return entry.message
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    func clearLogs() {
        logEntries.removeAll()
    }
}
