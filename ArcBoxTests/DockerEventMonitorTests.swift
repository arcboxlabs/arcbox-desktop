import XCTest
@testable import ArcBox
@testable import DockerClient

/// Tests for DockerEventMonitor's event filtering, notification dispatch, and debounce logic.
///
/// Strategy: call `handleEvent(_:)` directly (no real Docker socket needed),
/// observe NotificationCenter to assert which notifications are posted.
@MainActor
final class DockerEventMonitorTests: XCTestCase {

    private var monitor: DockerEventMonitor!

    override func setUp() {
        super.setUp()
        monitor = DockerEventMonitor()
    }

    override func tearDown() {
        monitor.stop()
        monitor = nil
        super.tearDown()
    }

    // MARK: - Helpers

    private func event(_ type: String, _ action: String) -> DockerClient.DockerEvent {
        DockerClient.DockerEvent(type: type, action: action, actorID: nil)
    }

    /// Wait for a notification within a timeout, returning true if received.
    private func expectNotification(
        _ name: Notification.Name,
        timeout: TimeInterval = 1.0,
        duringBlock block: () -> Void
    ) -> Bool {
        let expectation = expectation(forNotification: name, object: nil)
        block()
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        return result == .completed
    }

    /// Assert that a notification is NOT posted within the given timeout.
    private func refuteNotification(
        _ name: Notification.Name,
        timeout: TimeInterval = 0.5,
        duringBlock block: () -> Void
    ) {
        let expectation = expectation(forNotification: name, object: nil)
        expectation.isInverted = true
        block()
        wait(for: [expectation], timeout: timeout)
    }

    // MARK: - Container Events

    func test_containerStartEvent_postsContainerChanged() {
        let received = expectNotification(.dockerContainerChanged) {
            monitor.handleEvent(event("container", "start"))
        }
        XCTAssertTrue(received, "container/start should post .dockerContainerChanged")
    }

    func test_containerStartEvent_doesNotPostDockerDataChanged() {
        refuteNotification(.dockerDataChanged) {
            monitor.handleEvent(event("container", "start"))
        }
    }

    func test_containerDestroyEvent_postsBothNotifications() {
        let containerExp = expectation(forNotification: .dockerContainerChanged, object: nil)
        let dataExp = expectation(forNotification: .dockerDataChanged, object: nil)

        monitor.handleEvent(event("container", "destroy"))

        wait(for: [containerExp, dataExp], timeout: 1.0)
    }

    func test_containerCreateEvent_postsBothNotifications() {
        let containerExp = expectation(forNotification: .dockerContainerChanged, object: nil)
        let dataExp = expectation(forNotification: .dockerDataChanged, object: nil)

        monitor.handleEvent(event("container", "create"))

        wait(for: [containerExp, dataExp], timeout: 1.0)
    }

    // MARK: - Image Events

    func test_imageDeleteEvent_postsImageChanged() {
        let received = expectNotification(.dockerImageChanged) {
            monitor.handleEvent(event("image", "delete"))
        }
        XCTAssertTrue(received)
    }

    func test_imagePullEvent_postsImageChanged() {
        let received = expectNotification(.dockerImageChanged) {
            monitor.handleEvent(event("image", "pull"))
        }
        XCTAssertTrue(received)
    }

    // MARK: - Network Events

    func test_networkCreateEvent_postsNetworkChanged() {
        let received = expectNotification(.dockerNetworkChanged) {
            monitor.handleEvent(event("network", "create"))
        }
        XCTAssertTrue(received)
    }

    // MARK: - Volume Events

    func test_volumeDestroyEvent_postsVolumeChanged() {
        let received = expectNotification(.dockerVolumeChanged) {
            monitor.handleEvent(event("volume", "destroy"))
        }
        XCTAssertTrue(received)
    }

    // MARK: - Filtering

    func test_unknownAction_isFiltered() {
        refuteNotification(.dockerContainerChanged) {
            monitor.handleEvent(event("container", "exec_start"))
        }
    }

    func test_unknownType_isFiltered() {
        // daemon events should not trigger any notification
        refuteNotification(.dockerContainerChanged) {
            monitor.handleEvent(event("daemon", "reload"))
        }
        refuteNotification(.dockerImageChanged) {
            monitor.handleEvent(event("daemon", "reload"))
        }
    }

    // MARK: - Debounce

    func test_debounce_coalesces_rapidEvents() {
        // Send 3 rapid container events — should coalesce into 1 notification.
        let exp = expectation(forNotification: .dockerContainerChanged, object: nil)
        // Inverted extra expectation to verify it fires exactly once within window.
        let extraExp = expectation(forNotification: .dockerContainerChanged, object: nil)
        extraExp.isInverted = true
        // expectedFulfillmentCount on exp is 1 (default)

        monitor.handleEvent(event("container", "start"))
        monitor.handleEvent(event("container", "stop"))
        monitor.handleEvent(event("container", "die"))

        // Wait for the debounce to fire (~300ms) + margin
        wait(for: [exp], timeout: 1.0)
        // The inverted expectation verifies no second notification arrived
        wait(for: [extraExp], timeout: 0.5)
    }

    // MARK: - Stop Behavior

    func test_stop_cancelsDebounce() {
        // Post an event then immediately stop — debounce should be cancelled.
        refuteNotification(.dockerContainerChanged) {
            monitor.handleEvent(event("container", "start"))
            monitor.stop()
        }
    }

    // MARK: - Start Idempotency

    func test_start_isIdempotent() {
        // Calling start() twice should not crash or leave zombie tasks.
        // We can't directly assert task count, but we can verify the monitor
        // still works correctly after double-start.
        let docker = DockerClient()
        monitor.start(docker: docker)
        monitor.start(docker: docker)
        monitor.stop()
        // If we get here without crash/hang, idempotency holds.
    }
}
