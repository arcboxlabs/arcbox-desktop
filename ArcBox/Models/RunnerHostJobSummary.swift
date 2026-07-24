import FleetPlatformClient
import Foundation

nonisolated struct RunnerHostJobSummary: Equatable {
    let recordedCount: Int
    let todayCount: Int
    let completedCount: Int
    let unsuccessfulCount: Int
    let hasMoreHistory: Bool

    init(
        jobs: [FleetRunnerJob],
        hasMoreHistory: Bool,
        now: Date = .now,
        calendar: Calendar = .current
    ) {
        recordedCount = jobs.count
        todayCount = jobs.count { calendar.isDate($0.createdAt, inSameDayAs: now) }
        completedCount = jobs.count { $0.status == .completed }
        unsuccessfulCount = jobs.count {
            $0.status == .failed || $0.status == .canceled
        }
        self.hasMoreHistory = hasMoreHistory
    }

    var recordedCountDescription: String {
        hasMoreHistory ? "\(recordedCount)+" : "\(recordedCount)"
    }

    var successRate: Double? {
        let finishedCount = completedCount + unsuccessfulCount
        guard finishedCount > 0 else { return nil }
        return Double(completedCount) / Double(finishedCount)
    }
}
