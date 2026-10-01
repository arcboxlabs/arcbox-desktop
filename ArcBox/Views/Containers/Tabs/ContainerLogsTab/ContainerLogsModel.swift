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
    /// Derived from `logEntries` and the filters on read; not observed state.
    @ObservationIgnored private var filterCache = FilterCache()

    let maxLogEntries = 10_000
    /// How long lines may wait to be shown. Long enough to fold a burst into one list
    /// rebuild, short enough to still read as live.
    static let appendInterval = Duration.milliseconds(100)

    /// The lines the search text and stream filter keep, in buffer order.
    ///
    /// With no filter this is the buffer itself, shared, not copied. With one, it is
    /// a cache that follows the buffer incrementally: entries are allocated ids in
    /// arrival order and the buffer only ever grows at the tail and shrinks at the
    /// head, so a batch costs the batch and a trim costs the trimmed lines. Only a
    /// filter change rescans the buffer, which `localizedCaseInsensitiveContains`
    /// made the most expensive part of a batch (~24 ms at 6,000 lines).
    var filteredEntries: [LogEntry] {
        guard isFiltered else { return logEntries }
        let lastID = logEntries.last?.id ?? -1
        if filterCache.searchText != searchText || filterCache.streamFilter != streamFilter
            || lastID < filterCache.scannedID
        {
            // A new filter, or a buffer replaced by older lines: start over.
            filterCache = FilterCache(
                searchText: searchText,
                streamFilter: streamFilter,
                entries: logEntries.filter(matches),
                scannedID: lastID
            )
            return filterCache.entries
        }
        let firstID = logEntries.first?.id ?? Int.max
        filterCache.entries.removeFirst(filterCache.entries.prefix { $0.id < firstID }.count)
        if lastID > filterCache.scannedID {
            var start = logEntries.endIndex
            while start > logEntries.startIndex, logEntries[start - 1].id > filterCache.scannedID {
                start -= 1
            }
            filterCache.entries.append(contentsOf: logEntries[start...].filter(matches))
            filterCache.scannedID = lastID
        }
        return filterCache.entries
    }

    private var isFiltered: Bool {
        streamFilter != .all || !searchText.isEmpty
    }

    private func matches(_ entry: LogEntry) -> Bool {
        let streamMatches =
            switch streamFilter {
            case .all: true
            case .stdout: entry.stream == .stdout
            case .stderr: entry.stream == .stderr
            }
        return streamMatches && (searchText.isEmpty || entry.message.localizedCaseInsensitiveContains(searchText))
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

/// `filteredEntries` as of the last read: the matches among the buffer's lines
/// with `id <= scannedID`, for the filter `(searchText, streamFilter)`.
private struct FilterCache {
    var searchText = ""
    var streamFilter = LogStreamFilter.all
    var entries: [LogEntry] = []
    var scannedID = -1
}
