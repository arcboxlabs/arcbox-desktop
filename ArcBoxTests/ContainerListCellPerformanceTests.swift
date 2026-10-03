import AppKit
import XCTest

@testable import ArcBox

/// Throughput probes for the container list cells. They print their numbers so
/// a before/after comparison can be read off the test log; the assertions are
/// loose upper bounds that only catch a gross regression.
final class ContainerListCellPerformanceTests: XCTestCase {
    @MainActor
    func testContainerCellInitThroughput() {
        let clock = ContinuousClock()
        var cells: [ContainerTableCellView] = []
        cells.reserveCapacity(500)
        let elapsed = clock.measure {
            for _ in 0..<500 {
                cells.append(ContainerTableCellView())
            }
        }
        print("PERF ContainerTableCellView.init x500: \(elapsed)")
        XCTAssertEqual(cells.count, 500)
        XCTAssertLessThan(elapsed, .seconds(5))
    }

    @MainActor
    func testGroupCellInitThroughput() {
        let clock = ContinuousClock()
        var cells: [ContainerGroupTableCellView] = []
        cells.reserveCapacity(500)
        let elapsed = clock.measure {
            for _ in 0..<500 {
                cells.append(ContainerGroupTableCellView())
            }
        }
        print("PERF ContainerGroupTableCellView.init x500: \(elapsed)")
        XCTAssertEqual(cells.count, 500)
        XCTAssertLessThan(elapsed, .seconds(5))
    }

    @MainActor
    func testContainerCellConfigureThroughput() {
        let clock = ContinuousClock()
        let cell = ContainerTableCellView()
        let container = ContainerViewModel(
            id: "web",
            name: "web",
            image: "nginx:latest",
            state: .running,
            ports: [PortMapping(hostPort: 8080, containerPort: 80, protocol: "tcp")],
            createdAt: .distantPast,
            composeProject: "active",
            composeService: "web",
            labels: [:],
            cpuPercent: 0,
            memoryMB: 0,
            memoryLimitMB: 0
        )
        let elapsed = clock.measure {
            for index in 0..<500 {
                var current = container
                current.state = index.isMultiple(of: 2) ? .running : .stopped
                cell.configure(
                    container: current,
                    useDNS: false,
                    onOpenPort: { _ in },
                    onToggle: {},
                    onDelete: {}
                )
            }
        }
        print("PERF ContainerTableCellView.configure x500: \(elapsed)")
        XCTAssertLessThan(elapsed, .seconds(5))
    }
}
