import AppKit
import DockerClient
import SwiftUI

/// Filter for log streams
enum LogStreamFilter: String, CaseIterable, Identifiable {
    case all = "All"
    case stdout = "Stdout"
    case stderr = "Stderr"

    var id: String { rawValue }
}

/// Which stream a log line came from
enum LogStream {
    case stdout
    case stderr
}

/// A single log entry with metadata
struct LogEntry: Identifiable {
    let id = UUID()
    let timestamp: String?
    let stream: LogStream
    let message: String
}

/// Logs tab showing real container log output with streaming support
struct ContainerLogsTab: View {
    let container: ContainerViewModel

    @Environment(\.dockerClient) private var docker

    @State private var logEntries: [LogEntry] = []
    @State private var searchText = ""
    @State private var streamFilter: LogStreamFilter = .all
    @State private var isFollowing = true
    @State private var isLoading = true
    @State private var errorMessage: String?
    @State private var streamTask: Task<Void, Never>?

    private let maxLogEntries = 10_000

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

    var body: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack(spacing: 8) {
                // Search field
                HStack(spacing: 6) {
                    Image(systemName: "magnifyingglass")
                        .foregroundStyle(AppColors.textSecondary)
                        .font(.system(size: 12))
                    TextField("Search", text: $searchText)
                        .textFieldStyle(.plain)
                        .font(.system(size: 13))
                }
                .padding(.horizontal, 8)
                .padding(.vertical, 5)
                .background(AppColors.surfaceElevated)
                .clipShape(RoundedRectangle(cornerRadius: 6))

                // Stream filter
                Picker(selection: $streamFilter) {
                    ForEach(LogStreamFilter.allCases) { filter in
                        Text(filter.rawValue).tag(filter)
                    }
                } label: {
                    EmptyView()
                }
                .pickerStyle(.segmented)
                .frame(width: 180)

                Spacer()

                // Follow toggle
                Button(action: toggleFollow) {
                    Image(systemName: isFollowing ? "pause" : "arrow.down.to.line")
                        .font(.system(size: 12))
                        .foregroundStyle(isFollowing ? AppColors.accent : AppColors.textSecondary)
                }
                .buttonStyle(.plain)
                .help(isFollowing ? "Pause" : "Follow")

                Button(action: copyLogs) {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Copy logs")

                Button(action: clearLogs) {
                    Image(systemName: "trash")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textSecondary)
                }
                .buttonStyle(.plain)
                .help("Clear logs")
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)

            Divider()

            // Log content
            if isLoading && logEntries.isEmpty {
                Spacer()
                ProgressView("Loading logs...")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
            } else if let error = errorMessage, logEntries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundStyle(AppColors.textMuted)
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
            } else if filteredEntries.isEmpty {
                Spacer()
                Text(logEntries.isEmpty ? "No logs available" : "No matching logs")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
            } else {
                ScrollViewReader { proxy in
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: 0) {
                            ForEach(filteredEntries) { entry in
                                logLineView(entry)
                                    .id(entry.id)
                            }
                        }
                        .padding(.vertical, 4)
                    }
                    .onAppear {
                        // Jump to bottom immediately for historical logs
                        if let last = filteredEntries.last {
                            proxy.scrollTo(last.id, anchor: .bottom)
                        }
                    }
                    .onChange(of: logEntries.count) {
                        if isFollowing, let last = filteredEntries.last {
                            withAnimation(.easeOut(duration: 0.1)) {
                                proxy.scrollTo(last.id, anchor: .bottom)
                            }
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .task(id: container.id) {
            await startStreaming()
        }
        .onDisappear {
            cancelStreaming()
        }
    }

    @ViewBuilder
    private func logLineView(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if let ts = entry.timestamp {
                Text(formatTimestamp(ts))
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(AppColors.textMuted)
                    .lineLimit(1)
                Text(" ")
                    .font(.system(size: 12, design: .monospaced))
            }
            Text(entry.message)
                .font(.system(size: 12, design: .monospaced))
                .foregroundStyle(entry.stream == .stderr ? Color.red.opacity(0.85) : AppColors.text)
                .textSelection(.enabled)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 1)
    }

    /// ISO8601 parser for Docker RFC3339Nano timestamps
    private static let isoFormatter: ISO8601DateFormatter = {
        let f = ISO8601DateFormatter()
        f.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return f
    }()

    /// Display formatter in user's local timezone
    private static let displayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "HH:mm:ss"
        f.timeZone = .current
        return f
    }()

    /// Format Docker RFC3339Nano timestamp to local time
    private func formatTimestamp(_ ts: String) -> String {
        if let date = Self.isoFormatter.date(from: ts) {
            return Self.displayFormatter.string(from: date)
        }
        // Fallback: extract time part if parsing fails
        guard let tIndex = ts.firstIndex(of: "T"),
            let zIndex = ts.firstIndex(of: "Z") ?? ts.lastIndex(of: "+")
        else {
            return ts
        }
        let timePart = ts[ts.index(after: tIndex)..<zIndex]
        if let dotIndex = timePart.firstIndex(of: ".") {
            return String(timePart[timePart.startIndex..<dotIndex])
        }
        return String(timePart)
    }

    // MARK: - Actions

    private func startStreaming() async {
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
                id: container.id,
                tail: 500,
                timestamps: true
            )
            logEntries = historyLines.map { line in
                LogEntry(
                    timestamp: line.timestamp,
                    stream: line.stream == .stderr ? .stderr : .stdout,
                    message: line.message
                )
            }
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
                id: container.id,
                tail: 0,
                timestamps: true,
                since: sinceTimestamp
            )
            do {
                for try await line in stream {
                    if Task.isCancelled { break }
                    let entry = LogEntry(
                        timestamp: line.timestamp,
                        stream: line.stream == .stderr ? .stderr : .stdout,
                        message: line.message
                    )
                    logEntries.append(entry)
                    if logEntries.count > maxLogEntries {
                        logEntries.removeFirst(logEntries.count - maxLogEntries)
                    }
                }
            } catch {
                if !Task.isCancelled {
                    errorMessage = error.localizedDescription
                    isFollowing = false
                }
            }
        }
    }

    private func toggleFollow() {
        isFollowing.toggle()
        if isFollowing {
            startStreamTask()
        } else {
            cancelStreaming()
        }
    }

    private func cancelStreaming() {
        streamTask?.cancel()
        streamTask = nil
    }

    private func copyLogs() {
        let text = filteredEntries.map { entry in
            if let ts = entry.timestamp {
                return "\(ts) \(entry.message)"
            }
            return entry.message
        }.joined(separator: "\n")
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func clearLogs() {
        logEntries.removeAll()
    }
}
