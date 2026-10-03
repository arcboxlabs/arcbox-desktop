import XCTest

@testable import ArcBox

/// Tests for how a batch of container deaths is rendered as one notification.
@MainActor
final class ContainerCrashDigestTests: XCTestCase {

    private func crash(_ name: String, id: String? = nil, exitCode: Int = 1) -> ContainerCrash {
        ContainerCrash(containerID: id ?? name, name: name, exitCode: exitCode)
    }

    func testEmptyBatchSaysNothing() {
        XCTAssertNil(ContainerCrashDigest.notification(for: []))
    }

    func testSingleCrashNamesTheContainerAndSelectsIt() {
        let notification = ContainerCrashDigest.notification(for: [crash("api", id: "abc", exitCode: 137)])

        XCTAssertEqual(notification?.title, "Container exited")
        XCTAssertEqual(notification?.body, "api exited with code 137.")
        XCTAssertEqual(notification?.destination, .section(.containers, id: "abc"))
    }

    /// A failing `compose up` takes several containers down at once; one banner
    /// per container is what this exists to prevent.
    func testBatchIsCountedAndListed() {
        let notification = ContainerCrashDigest.notification(
            for: [crash("api"), crash("worker"), crash("db")])

        XCTAssertEqual(notification?.title, "3 containers exited")
        XCTAssertEqual(notification?.body, "api, worker, db.")
        XCTAssertEqual(notification?.destination, .section(.containers, id: nil))
    }

    /// Fewer names than the cap: nothing is held back, so nothing trails.
    func testShortBatchListsEveryName() {
        let notification = ContainerCrashDigest.notification(for: [crash("api"), crash("worker")])

        XCTAssertEqual(notification?.title, "2 containers exited")
        XCTAssertEqual(notification?.body, "api, worker.")
    }

    func testLongBatchTruncatesTheNameList() {
        let notification = ContainerCrashDigest.notification(
            for: [crash("api"), crash("worker"), crash("db"), crash("cache"), crash("proxy")])

        XCTAssertEqual(notification?.title, "5 containers exited")
        XCTAssertEqual(notification?.body, "api, worker, db and 2 more.")
    }

    /// One container dying repeatedly inside a single window is one story.
    func testRepeatsOfOneContainerCollapse() {
        let notification = ContainerCrashDigest.notification(
            for: [crash("api", id: "abc"), crash("api", id: "abc"), crash("api", id: "abc")])

        XCTAssertEqual(notification?.title, "Container exited")
    }

    /// The digest is the current state of things, so a later one replaces it.
    func testDigestsShareAnIdentifier() {
        let single = ContainerCrashDigest.notification(for: [crash("api")])
        let batch = ContainerCrashDigest.notification(for: [crash("api"), crash("worker")])

        XCTAssertEqual(single?.identifier, batch?.identifier)
    }

    func testDigestIsSwitchableOnItsOwn() {
        XCTAssertEqual(ContainerCrashDigest.notification(for: [crash("api")])?.category, .container)
    }
}
