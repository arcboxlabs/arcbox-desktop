import SwiftUI

/// One log line: its local time, then the message in the stream's color.
///
/// Rows are what the batch regression test counts. A `LazyVStack` evaluates only
/// the rows it lays out, so a batch of appended lines must evaluate the new rows
/// and the visible ones, never the buffer.
struct ContainerLogsRow: View {
    let entry: LogEntry

    var body: some View {
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
        .recordingBodyEvaluation(of: Self.self)
    }
}
