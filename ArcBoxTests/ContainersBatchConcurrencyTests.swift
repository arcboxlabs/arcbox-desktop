import XCTest

@testable import ArcBox

@MainActor
final class ContainersBatchConcurrencyTests: XCTestCase {
    /// The regression this guards: a selection used to put one request per container in
    /// flight at once, which starved the Docker client's connection pool and failed the
    /// next list refresh with `getConnectionFromPoolTimeout`.
    func testNoMoreThanTheLimitRunAtOnce() async {
        let vm = ContainersViewModel()
        let meter = Meter()

        let errors = await vm.batch((0..<40).map(String.init)) { _ in
            await meter.enter()
            try? await Task.sleep(for: .milliseconds(5))
            await meter.leave()
            return nil
        }

        let peak = await meter.peak
        let finished = await meter.finished
        XCTAssertEqual(errors, [])
        XCTAssertEqual(finished, 40, "every container must be acted on")
        XCTAssertEqual(peak, ContainersViewModel.batchConcurrency)
    }

    func testFailuresAreCollectedAndTheRestStillRun() async {
        let vm = ContainersViewModel()
        let meter = Meter()

        let errors = await vm.batch(["ok", "bad", "ok", "worse"]) { id in
            await meter.enter()
            await meter.leave()
            return id == "ok" ? nil : id
        }

        let finished = await meter.finished
        XCTAssertEqual(finished, 4)
        XCTAssertEqual(errors.sorted(), ["bad", "worse"])
    }

    private actor Meter {
        private(set) var peak = 0
        private(set) var finished = 0
        private var inFlight = 0

        func enter() {
            inFlight += 1
            peak = max(peak, inFlight)
        }

        func leave() {
            inFlight -= 1
            finished += 1
        }
    }
}
