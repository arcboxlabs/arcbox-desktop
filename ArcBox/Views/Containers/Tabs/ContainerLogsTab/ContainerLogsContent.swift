import SwiftUI

/// The log lines, or the placeholder that stands in for them.
///
/// This is the one view a batch of appended lines re-evaluates.
struct ContainerLogsContent: View {
    let model: ContainerLogsModel

    var body: some View {
        VStack(spacing: 0) {
            if model.isLoading && model.logEntries.isEmpty {
                Spacer()
                ProgressView("Loading logs...")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
            } else if let error = model.errorMessage, model.logEntries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundStyle(AppColors.textMuted)
                        .accessibilityHidden(true)
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
            } else if model.filteredEntries.isEmpty {
                Spacer()
                Text(model.logEntries.isEmpty ? "No logs available" : "No matching logs")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
            } else {
                logList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .recordingBodyEvaluation(of: Self.self)
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(model.filteredEntries) { entry in
                        logLineView(entry)
                            .id(entry.id)
                    }
                }
                .padding(.vertical, 4)
            }
            .onAppear {
                // Jump to bottom immediately for historical logs
                if let last = model.filteredEntries.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
            // Unanimated: animating a jump to the end of a lazy stack makes SwiftUI
            // walk the list to resolve the target, and a followed container pays that
            // on every line.
            .onChange(of: model.logEntries.count) {
                if model.isFollowing, let last = model.filteredEntries.last {
                    proxy.scrollTo(last.id, anchor: .bottom)
                }
            }
        }
    }

    private func logLineView(_ entry: LogEntry) -> some View {
        HStack(alignment: .top, spacing: 0) {
            if let time = entry.time {
                Text(time)
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
}
