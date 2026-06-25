import SwiftUI

extension ContainerLogsTab {
    var toolbarView: some View {
        HStack(spacing: 8) {
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
    }

    @ViewBuilder
    var logContentView: some View {
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

    @ViewBuilder
    func logLineView(_ entry: LogEntry) -> some View {
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
}
