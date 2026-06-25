import AppKit
import DockerClient
import Foundation

extension ContainerLogsTab {
    func startStreaming() async {
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

    func startStreamTask(since: Int? = nil) {
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
