import XCTest

@testable import ArcBox

@MainActor
final class GuestDataMountTests: XCTestCase {
    private var arcboxRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("ArcBox")
    }

    func testVolumePathMapsUnderArcBox() {
        let url = GuestDataMount.hostURL(forGuestPath: "/var/lib/docker/volumes/pgdata/_data")
        XCTAssertEqual(url, arcboxRoot.appendingPathComponent("volumes/pgdata/_data"))
    }

    func testOverlayLayerPathMapsUnderArcBox() {
        let url = GuestDataMount.hostURL(forGuestPath: "/var/lib/docker/overlay2/abc123/diff")
        XCTAssertEqual(url, arcboxRoot.appendingPathComponent("overlay2/abc123/diff"))
    }

    func testDataRootItselfMapsToArcBoxRoot() {
        XCTAssertEqual(GuestDataMount.hostURL(forGuestPath: "/var/lib/docker"), arcboxRoot)
        XCTAssertEqual(GuestDataMount.hostURL(forGuestPath: "/var/lib/docker/"), arcboxRoot)
    }

    func testPathOutsideDataRootIsRejected() {
        XCTAssertNil(GuestDataMount.hostURL(forGuestPath: "/etc/passwd"))
        XCTAssertNil(GuestDataMount.hostURL(forGuestPath: "/home/user/project"))
    }

    func testSiblingPrefixIsNotMistakenForDataRoot() {
        // Must not treat /var/lib/dockerfoo as being under /var/lib/docker.
        XCTAssertNil(GuestDataMount.hostURL(forGuestPath: "/var/lib/dockerfoo/x"))
    }

    func testSurroundingWhitespaceIsTrimmed() {
        let url = GuestDataMount.hostURL(forGuestPath: "  /var/lib/docker/volumes/v/_data\n")
        XCTAssertEqual(url, arcboxRoot.appendingPathComponent("volumes/v/_data"))
    }

    func testTraversalComponentsAreRejected() {
        // Guest paths can come from image labels; ".." must never escape the export.
        XCTAssertNil(GuestDataMount.hostURL(forGuestPath: "/var/lib/docker/.."))
        XCTAssertNil(GuestDataMount.hostURL(forGuestPath: "/var/lib/docker/../../Users/x/.ssh"))
        XCTAssertNil(GuestDataMount.hostURL(forGuestPath: "/var/lib/docker/volumes/../../../etc"))
        XCTAssertNil(GuestDataMount.hostURL(forGuestPath: "/var/lib/docker/./volumes"))
    }

    func testDoubleSlashesDoNotBypassTraversalCheck() {
        XCTAssertNil(GuestDataMount.hostURL(forGuestPath: "/var/lib/docker//..//etc"))
    }
}
