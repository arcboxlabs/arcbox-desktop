import XCTest

@testable import ArcBox

@MainActor
final class GuestDataMountTests: XCTestCase {
    /// Where the daemon mounts the docker export: `docker/` under the host
    /// mount root `~/ArcBox`.
    private var arcboxRoot: URL {
        FileManager.default.homeDirectoryForCurrentUser.appending(path: "ArcBox/docker", directoryHint: .isDirectory)
    }

    func testExportIsMountedUnderTheHostMountRoot() {
        let home = FileManager.default.homeDirectoryForCurrentUser
        XCTAssertEqual(GuestDataMount.hostMountRoot, home.appending(path: "ArcBox", directoryHint: .isDirectory))
        XCTAssertEqual(GuestDataMount.rootURL, arcboxRoot)
    }

    func testPathMappingDoesNotInferDirectoriesFromTheFilesystem() throws {
        let exportRoot = FileManager.default.temporaryDirectory.appending(
            path: UUID().uuidString, directoryHint: .isDirectory)
        let existingDirectory = exportRoot.appending(path: "volume", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: existingDirectory, withIntermediateDirectories: true)
        addTeardownBlock { try FileManager.default.removeItem(at: exportRoot) }

        let url = try XCTUnwrap(
            GuestDataMount.hostURL(forGuestPath: "/var/lib/docker/volume", exportRoot: exportRoot))

        XCTAssertEqual(url.path, existingDirectory.path)
        XCTAssertFalse(url.hasDirectoryPath, "Path mapping must not query the export to infer directory state.")
    }

    func testVolumePathMapsUnderArcBox() {
        let url = GuestDataMount.hostURL(forGuestPath: "/var/lib/docker/volumes/pgdata/_data")
        XCTAssertEqual(url, arcboxRoot.appending(path: "volumes/pgdata/_data", directoryHint: .inferFromPath))
    }

    func testOverlayLayerPathMapsUnderArcBox() {
        let url = GuestDataMount.hostURL(forGuestPath: "/var/lib/docker/overlay2/abc123/diff")
        XCTAssertEqual(url, arcboxRoot.appending(path: "overlay2/abc123/diff", directoryHint: .inferFromPath))
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
        XCTAssertEqual(url, arcboxRoot.appending(path: "volumes/v/_data", directoryHint: .inferFromPath))
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

    func testContainerdSnapshotPathMapsUnderContainerdChildExport() {
        let url = GuestDataMount.hostURL(
            forGuestPath:
                "/var/lib/containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/269/fs")
        XCTAssertEqual(
            url,
            arcboxRoot.appending(
                path: "containerd/io.containerd.snapshotter.v1.overlayfs/snapshots/269/fs",
                directoryHint: .inferFromPath))
    }

    func testContainerdRootItselfMapsToChildExportRoot() {
        XCTAssertEqual(
            GuestDataMount.hostURL(forGuestPath: "/var/lib/containerd"),
            arcboxRoot.appending(path: "containerd", directoryHint: .isDirectory))
    }

    func testContainerdSiblingPrefixIsRejected() {
        XCTAssertNil(GuestDataMount.hostURL(forGuestPath: "/var/lib/containerdfoo/x"))
    }

    func testContainerdTraversalComponentsAreRejected() {
        XCTAssertNil(GuestDataMount.hostURL(forGuestPath: "/var/lib/containerd/../docker"))
        XCTAssertNil(GuestDataMount.hostURL(forGuestPath: "/var/lib/containerd/./snapshots"))
    }
}
