import DockerClient
import SwiftUI

/// Logs tab showing real container log output with streaming support
struct ContainerLogsTab: View {
    let container: ContainerViewModel

    @Environment(\.dockerClient) var docker

    @State var logEntries: [LogEntry] = []
    @State var searchText = ""
    @State var streamFilter: LogStreamFilter = .all
    @State var isFollowing = true
    @State var isLoading = true
    @State var errorMessage: String?
    @State var streamTask: Task<Void, Never>?

    let maxLogEntries = 10_000

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
            toolbarView
            Divider()
            logContentView
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
}
