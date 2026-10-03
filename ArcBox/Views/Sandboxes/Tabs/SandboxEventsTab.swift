import ArcBoxClient
import SwiftUI

/// Events tab: live lifecycle event feed for one sandbox.
///
/// Events come from the app-wide `SandboxEventMonitor` stream; the feed starts
/// when the app connects, so events emitted before launch are not shown.
struct SandboxEventsTab: View {
    let sandboxID: String

    @Environment(SandboxEventMonitor.self) private var monitor

    private var events: [SandboxEventRecord] {
        monitor.events(for: sandboxID)
    }

    var body: some View {
        VStack(spacing: 0) {
            scopeNotice
            Divider()
            if events.isEmpty {
                VStack(spacing: 10) {
                    Spacer()
                    Image(systemName: "bolt")
                        .font(.system(size: 24))
                        .foregroundStyle(AppColors.textMuted)
                    Text("No events retained for this sandbox.")
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textSecondary)
                    Text("Events sent before ArcBox connected or while it was disconnected aren’t available.")
                        .font(.system(size: 12))
                        .foregroundStyle(AppColors.textMuted)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                ScrollView {
                    LazyVStack(spacing: 0) {
                        ForEach(events) { event in
                            eventRow(event)
                            Divider()
                        }
                    }
                }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
    }

    private var scopeNotice: some View {
        Label(
            "Events received while ArcBox is connected. The latest \(SandboxEventMonitor.maxRecentEvents) across all sandboxes are kept until quit.",
            systemImage: "info.circle"
        )
        .font(.system(size: 11))
        .foregroundStyle(AppColors.textMuted)
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
    }

    private func eventRow(_ event: SandboxEventRecord) -> some View {
        HStack(spacing: 10) {
            StatusBadge(color: actionColor(event.action), label: event.action)

            Text(relativeTime(from: event.timestamp))
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textSecondary)

            if !event.attributes.isEmpty {
                Text(
                    event.attributes.map { "\($0.key)=\($0.value)" }
                        .sorted()
                        .joined(separator: "  ")
                )
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(AppColors.textMuted)
                .lineLimit(1)
                .truncationMode(.tail)
            }

            Spacer()
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func actionColor(_ action: String) -> Color {
        switch action {
        case "created", "ready", "running":
            AppColors.running
        case "idle", "stopping":
            AppColors.warning
        case "failed":
            AppColors.error
        default:
            AppColors.stopped
        }
    }
}
