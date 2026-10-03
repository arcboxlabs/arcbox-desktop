import SwiftUI

/// Search field, stream filter, and stream controls of the logs tab.
///
/// Reads only `searchText`, `streamFilter`, and `isFollowing`, so appended log
/// lines never re-evaluate it. That matters because the segmented stream
/// filter is an `NSSegmentedControl` whose every measurement re-runs its own
/// view graph — measured at ~1.3 ms per layout pass, the ARCBOX-DESKTOP-SWIFT-T
/// hang cluster when a followed container logs steadily.
struct ContainerLogsToolbar: View {
    @Bindable var model: ContainerLogsModel

    var body: some View {
        HStack(spacing: 8) {
            HStack(spacing: 6) {
                Image(systemName: "magnifyingglass")
                    .foregroundStyle(AppColors.textSecondary)
                    .font(.system(size: 12))
                    .accessibilityHidden(true)
                TextField("Search", text: $model.searchText)
                    .textFieldStyle(.plain)
                    .font(.system(size: 13))
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(AppColors.surfaceElevated)
            .clipShape(RoundedRectangle(cornerRadius: 6))

            Picker("Stream", selection: $model.streamFilter) {
                ForEach(LogStreamFilter.allCases) { filter in
                    Text(filter.rawValue).tag(filter)
                }
            }
            .labelsHidden()
            .pickerStyle(.segmented)
            .frame(width: 180)

            Spacer()

            Button {
                model.toggleFollow()
            } label: {
                Image(systemName: model.isFollowing ? "pause" : "arrow.down.to.line")
                    .font(.system(size: 12))
                    .foregroundStyle(model.isFollowing ? AppColors.accent : AppColors.textSecondary)
            }
            .buttonStyle(.plain)
            .help(model.isFollowing ? "Pause" : "Follow")
            .accessibilityLabel(model.isFollowing ? "Pause following" : "Follow new output")

            Button {
                model.copyLogs()
            } label: {
                Image(systemName: "doc.on.doc")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Copy logs")
            .accessibilityLabel("Copy logs")

            Button {
                model.clearLogs()
            } label: {
                Image(systemName: "trash")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary)
            }
            .buttonStyle(.plain)
            .help("Clear logs")
            .accessibilityLabel("Clear logs")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .recordingBodyEvaluation(of: Self.self)
    }
}
