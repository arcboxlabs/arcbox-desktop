import FleetPlatformClient
import SwiftUI

struct RunnerJobRow: View {
    let job: RunnerJobListItem
    let isSelected: Bool
    let onSelect: () -> Void

    var body: some View {
        Button(action: onSelect) {
            HStack(spacing: 10) {
                Image(systemName: job.os == "darwin" ? "macwindow" : "shippingbox")
                    .foregroundStyle(isSelected ? AppColors.onAccent : AppColors.accent)

                VStack(alignment: .leading, spacing: 2) {
                    Text(job.repository ?? job.id)
                        .font(job.repository == nil ? .body.monospaced() : .body)
                        .lineLimit(1)
                    Text("\(job.os)/\(job.arch) · \(job.id)")
                        .font(.caption)
                        .foregroundStyle(
                            isSelected ? AppColors.onAccent.opacity(0.75) : AppColors.textSecondary
                        )
                        .lineLimit(1)
                }

                Spacer()

                StatusBadge(color: job.status.color, label: job.status.label)
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .padding(.vertical, 4)
        .listRowBackground(isSelected ? AppColors.selection : Color.clear)
        .foregroundStyle(isSelected ? AppColors.onAccent : AppColors.text)
        .accessibilityElement(children: .combine)
        .accessibilityLabel("\(job.repository ?? job.id), \(job.status.label)")
        .accessibilityHint("Shows job details")
    }
}

extension FleetRunnerJobStatus {
    fileprivate var label: String {
        switch self {
        case .queued: "Queued"
        case .provisioning: "Provisioning"
        case .running: "Running"
        case .completed: "Completed"
        case .failed: "Failed"
        case .canceled: "Canceled"
        }
    }

    fileprivate var color: Color {
        switch self {
        case .queued: AppColors.stopped
        case .provisioning: AppColors.warning
        case .running, .completed: AppColors.running
        case .failed: AppColors.error
        case .canceled: AppColors.stopped
        }
    }
}
