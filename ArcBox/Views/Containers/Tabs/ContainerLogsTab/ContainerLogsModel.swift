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
    /// The buffer. `append(_:)` is the one writer the filter cache follows; a write
    /// from anywhere else — a history load, `clearLogs`, a test — rescans on the
    /// next read.
    var logEntries: [LogEntry] = [] {
        didSet {
            if !isAppending { filterCache.scannedLastID = nil }
        }
    }
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
    @ObservationIgnored private var isAppending = false

    let maxLogEntries = 10_000
    /// How many lines a trim at the cap drops at once. Dropping the head of a
    /// 10,000-entry array, and the copy forced by the `ForEach` still holding the
    /// previous array, are linear in the buffer; paying them once per block instead
    /// of once per batch keeps a batch at the cap the price of a batch below it.
    static let trimBlock = 1_000
    /// How long lines may wait to be shown. Long enough to fold a burst into one list
    /// rebuild, short enough to still read as live.
    static let appendInterval = Duration.milliseconds(100)

    /// The lines the search text and stream filter keep, in buffer order.
    ///
    /// With no filter this is the buffer itself, shared, not copied. With one, it is
    /// a cache that follows `append(_:)`: ids are allocated in arrival order, so a
    /// batch extends the cache by the lines past the last id it scanned and a trim
    /// drops the matches below the buffer's first id — the batch costs the batch.
    /// Only a filter change, or a write to `logEntries` from anywhere else, rescans
    /// the buffer, the pass `localizedCaseInsensitiveContains` made the most
    /// expensive part of a batch (~24 ms at 6,000 lines).
    var filteredEntries: [LogEntry] {
        guard isFiltered else { return logEntries }
        guard filterCache.searchText == searchText, filterCache.streamFilter == streamFilter,
            let scannedLastID = filterCache.scannedLastID
        else {
            #if DEBUG
                ContainerLogsDiagnostics.recordFilterRescan()
            #endif
            filterCache = FilterCache(
                searchText: searchText,
                streamFilter: streamFilter,
                entries: logEntries.filter(matches),
                scannedLastID: logEntries.last?.id
            )
            return filterCache.entries
        }
        guard let first = logEntries.first, let last = logEntries.last else {
            filterCache.entries = []
            return []
        }
        filterCache.entries.removeFirst(filterCache.entries.prefix { $0.id < first.id }.count)
        var start = logEntries.endIndex
        while start > logEntries.startIndex, logEntries[start - 1].id > scannedLastID {
            start -= 1
        }
        filterCache.entries.append(contentsOf: logEntries[start...].filter(matches))
        filterCache.scannedLastID = last.id
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

    /// Appends one batch of streamed lines; past `maxLogEntries` the oldest
    /// `trimBlock` lines go with the excess.
    ///
    /// Every line a followed container logs lands here, so this is the path whose
    /// cost the batch regression test pins.
    func append(_ lines: [DockerLogLine]) {
        isAppending = true
        defer { isAppending = false }
        logEntries.append(contentsOf: lines.map(LogEntry.init))
        if logEntries.count > maxLogEntries {
            logEntries.removeFirst(logEntries.count - maxLogEntries + Self.trimBlock)
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

/// `filteredEntries` as of the last read: the matches, for the filter
/// `(searchText, streamFilter)`, among the buffer's lines up to `scannedLastID`.
private struct FilterCache {
    var searchText = ""
    var streamFilter = LogStreamFilter.all
    var entries: [LogEntry] = []
    /// `nil` when the buffer was empty or was written outside `append(_:)`: rescan.
    var scannedLastID: Int?
}
