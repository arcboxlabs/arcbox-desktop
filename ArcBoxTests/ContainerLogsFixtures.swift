import DockerClient
import Foundation

@testable import ArcBox

/// What the logs tab tests feed a `ContainerLogsModel`.
@MainActor
enum ContainerLogsFixtures {
    static let container = ContainerViewModel(
        id: "container-1",
        name: "web",
        image: "nginx:latest",
        state: .running,
        ports: [],
        createdAt: Date(),
        composeProject: nil,
        composeService: nil,
        labels: [:],
        cpuPercent: 0,
        memoryMB: 0,
        memoryLimitMB: 0
    )

    /// `count` lines as Docker delivers them — RFC3339Nano timestamps, every
    /// seventh line an error on stderr — numbered from `next`, which advances.
    static func lines(from next: inout Int, count: Int) -> [DockerLogLine] {
        var lines: [DockerLogLine] = []
        lines.reserveCapacity(count)
        for _ in 0..<count {
            let index = next
            next += 1
            let isError = index % 7 == 6
            lines.append(
                DockerLogLine(
                    stream: isError ? .stderr : .stdout,
                    message: isError
                        ? "error: request \(index) failed after \(index % 97) ms"
                        : "info: request \(index) served in \(index % 97) ms",
                    timestamp: timestamp(index)
                ))
        }
        return lines
    }

    private static func timestamp(_ index: Int) -> String {
        let hours = (index / 3600) % 24
        let minutes = (index / 60) % 60
        let seconds = index % 60
        let nanos = (index * 1_234_567) % 1_000_000_000
        return String(format: "2026-10-01T%02d:%02d:%02d.%09dZ", hours, minutes, seconds, nanos)
    }
}
