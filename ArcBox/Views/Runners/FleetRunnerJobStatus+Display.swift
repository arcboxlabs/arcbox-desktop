import FleetPlatformClient
import SwiftUI

extension FleetRunnerJobStatus {
    var displayName: String {
        switch self {
        case .queued: "Queued"
        case .provisioning: "Provisioning"
        case .running: "Running"
        case .completed: "Completed"
        case .failed: "Failed"
        case .canceled: "Canceled"
        }
    }

    var color: Color {
        switch self {
        case .queued: AppColors.stopped
        case .provisioning: AppColors.warning
        case .running, .completed: AppColors.running
        case .failed: AppColors.error
        case .canceled: AppColors.stopped
        }
    }
}
