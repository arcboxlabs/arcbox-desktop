import XCTest

@testable import ArcBox

final class LayeredRootFSTests: XCTestCase {
    // MARK: merge precedence

    /// Creates a directory that exists but cannot be listed — the real
    /// "the layer is there and will not open" condition.
    ///
    /// A regular file standing in for a directory does NOT reproduce it: that
    /// is ordinary overlay shadowing, which the merge is supposed to accept
    /// silently, so using one here would assert the opposite of the intent.
    private func makeUnreadableDirectory(at url: URL) throws {
        try XCTSkipIf(getuid() == 0, "permissions do not restrict root")
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o000], ofItemAtPath: url.path)
        addTeardownBlock {
            try? FileManager.default.setAttributes(
                [.posixPermissions: 0o755], ofItemAtPath: url.path)
        }
    }

    private func item(
        _ name: String, isWhiteout: Bool = false, layer: String = "l"
    )
        -> LocalRootFSService.LayerItem
    {
        let entry = LocalFileEntry(
            url: URL(fileURLWithPath: "/\(layer)/\(name)"),
            name: name,
            isDirectory: false,
            isSymbolicLink: false,
            sizeBytes: 0,
            modifiedDate: nil,
            kind: "Document",
            children: nil,
            loadError: nil
        )
        return LocalRootFSService.LayerItem(entry: entry, isWhiteout: isWhiteout)
    }

    func testHigherLayerWinsSameName() {
        let merged = LayeredRootFS.merge([
            [item("app.conf", layer: "upper")],
            [item("app.conf", layer: "lower")],
        ])

        XCTAssertEqual(merged.map(\.name), ["app.conf"])
        // The container's own copy must win over the image's, or the tab
        // would show pre-edit content for every modified file.
        XCTAssertEqual(merged[0].url.path, "/upper/app.conf")
    }

    func testLayersUnionDistinctNames() {
        let merged = LayeredRootFS.merge([
            [item("written-by-container", layer: "upper")],
            [item("from-image", layer: "lower")],
        ])

        XCTAssertEqual(merged.map(\.name), ["from-image", "written-by-container"])
    }

    func testWhiteoutHidesItselfAndLowerEntry() {
        // Deleting an image file inside a container leaves a whiteout in the
        // upper layer; both it and the file it deletes must disappear.
        let merged = LayeredRootFS.merge([
            [item("deleted", isWhiteout: true, layer: "upper")],
            [item("deleted", layer: "lower"), item("kept", layer: "lower")],
        ])

        XCTAssertEqual(merged.map(\.name), ["kept"])
    }

    func testWhiteoutOnlyShadowsLowerLayers() {
        // A whiteout in a middle layer must not hide a higher layer's file.
        let merged = LayeredRootFS.merge([
            [item("resurrected", layer: "upper")],
            [item("resurrected", isWhiteout: true, layer: "mid")],
            [item("resurrected", layer: "lower")],
        ])

        XCTAssertEqual(merged.map(\.name), ["resurrected"])
        XCTAssertEqual(merged[0].url.path, "/upper/resurrected")
    }

    func testMergedEntriesAreSortedByName() {
        let merged = LayeredRootFS.merge([
            [item("zeta", layer: "upper")],
            [item("alpha", layer: "lower")],
        ])

        XCTAssertEqual(merged.map(\.name), ["alpha", "zeta"])
    }

    // MARK: relative path mapping

    func testRelativePathResolvesAcrossLayers() throws {
        let unwrapped = try XCTUnwrap(
            LayeredRootFS(layers: [
                URL(fileURLWithPath: "/mnt/upper"),
                URL(fileURLWithPath: "/mnt/lower"),
            ]))

        XCTAssertEqual(unwrapped.relativePath(forHostURL: URL(fileURLWithPath: "/mnt/upper")), "")
        XCTAssertEqual(
            unwrapped.relativePath(forHostURL: URL(fileURLWithPath: "/mnt/lower/etc/nginx")),
            "etc/nginx"
        )
        // A URL from outside the stack must not be mistaken for layer content.
        XCTAssertNil(unwrapped.relativePath(forHostURL: URL(fileURLWithPath: "/elsewhere/etc")))
    }

    func testRelativePathDoesNotMatchSiblingPrefix() throws {
        // "/mnt/upper-backup" shares a string prefix with "/mnt/upper" but is
        // a different directory; treating it as layer content would browse
        // the wrong tree.
        let stack = try XCTUnwrap(LayeredRootFS(layers: [URL(fileURLWithPath: "/mnt/upper")]))

        XCTAssertNil(
            stack.relativePath(forHostURL: URL(fileURLWithPath: "/mnt/upper-backup/etc")))
    }

    func testEmptyStackIsRejected() {
        XCTAssertNil(LayeredRootFS(layers: []))
    }

    // MARK: on-disk merge

    func testListDirectoryMergesRealDirectories() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let upper = root.appendingPathComponent("upper/etc", isDirectory: true)
        let lower = root.appendingPathComponent("lower/etc", isDirectory: true)
        try FileManager.default.createDirectory(at: upper, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: lower, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "container".write(to: upper.appendingPathComponent("hosts"), atomically: true, encoding: .utf8)
        try "image".write(to: lower.appendingPathComponent("hosts"), atomically: true, encoding: .utf8)
        try "image".write(to: lower.appendingPathComponent("resolv.conf"), atomically: true, encoding: .utf8)

        let stack = try XCTUnwrap(
            LayeredRootFS(layers: [
                root.appendingPathComponent("upper", isDirectory: true),
                root.appendingPathComponent("lower", isDirectory: true),
            ]))
        let listing = stack.listDirectory(relativePath: "etc", showHiddenFiles: false)

        XCTAssertEqual(listing.entries.map(\.name), ["hosts", "resolv.conf"])
        XCTAssertEqual(try String(contentsOf: listing.entries[0].url, encoding: .utf8), "container")
        XCTAssertEqual(listing.excludedLayers, [])
    }

    func testListDirectorySkipsLayersMissingTheDirectory() throws {
        // Most layers do not carry most directories; a layer without the path
        // must contribute nothing rather than failing the whole listing.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let lower = root.appendingPathComponent("lower/opt", isDirectory: true)
        try FileManager.default.createDirectory(at: lower, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("upper", isDirectory: true),
            withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "x".write(to: lower.appendingPathComponent("tool"), atomically: true, encoding: .utf8)

        let stack = try XCTUnwrap(
            LayeredRootFS(layers: [
                root.appendingPathComponent("upper", isDirectory: true),
                root.appendingPathComponent("lower", isDirectory: true),
            ]))

        let listing = stack.listDirectory(relativePath: "opt", showHiddenFiles: false)
        XCTAssertEqual(listing.entries.map(\.name), ["tool"])
        // A layer that simply lacks the path is normal, not a read failure —
        // counting it would put a permanent warning on every browse.
        XCTAssertEqual(listing.excludedLayers, [])
    }

    // MARK: whiteout classification

    func testRealCharacterDeviceIsNotAWhiteout() throws {
        // Overlay whiteouts are character devices of rdev 0:0. Layers also
        // carry legitimate character devices (an image shipping /dev/null,
        // a privileged container's nodes); classifying those as deletions
        // would hide both the device and whatever it shadows below.
        let devices = try LocalRootFSService.listLayerItems(
            at: URL(fileURLWithPath: "/dev"), showHiddenFiles: true)
        let null = try XCTUnwrap(devices.first { $0.entry.name == "null" })

        XCTAssertFalse(null.isWhiteout)
    }

    func testRegularFileIsNotAWhiteout() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "x".write(to: root.appendingPathComponent("file"), atomically: true, encoding: .utf8)

        let items = try LocalRootFSService.listLayerItems(at: root, showHiddenFiles: false)

        XCTAssertEqual(items.map(\.isWhiteout), [false])
    }

    func testGuestEntriesUseNeutralKinds() throws {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        let file = root.appendingPathComponent("settings.conf")
        let executable = root.appendingPathComponent("run")
        let directory = root.appendingPathComponent("Example.app", isDirectory: true)
        let symlink = root.appendingPathComponent("settings-link")
        try "config".write(to: file, atomically: true, encoding: .utf8)
        try "#!/bin/sh".write(to: executable, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes(
            [.posixPermissions: 0o755], ofItemAtPath: executable.path)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: symlink, withDestinationURL: file)

        let entries = try LocalRootFSService.listDirectory(at: root, showHiddenFiles: true)
        let byName = Dictionary(uniqueKeysWithValues: entries.map { ($0.name, $0) })

        XCTAssertEqual(byName["settings.conf"]?.kind, "File")
        XCTAssertEqual(byName["run"]?.kind, "Executable")
        XCTAssertEqual(byName["Example.app"]?.kind, "Directory")
        XCTAssertTrue(try XCTUnwrap(byName["Example.app"]?.isExpandable))
        XCTAssertEqual(byName["settings-link"]?.kind, "Symlink")
    }

    @MainActor
    func testDisplayPathDoesNotExposeHostLayerPath() {
        let etc = LocalFileNode(entry: item("etc", layer: "host/snapshot").entry, parent: nil)
        let hosts = LocalFileNode(entry: item("hosts", layer: "host/snapshot/etc").entry, parent: etc)

        XCTAssertEqual(hosts.displayPath(rootPath: "/"), "/etc/hosts")
    }

    func testListDirectoryReportsExcludedLayers() throws {
        // A path that exists but will not list (here: a regular file where a
        // directory is expected) is a real hole in the merge — the caller has
        // to be able to tell the user the view is incomplete.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let good = root.appendingPathComponent("good/etc", isDirectory: true)
        try FileManager.default.createDirectory(at: good, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: root.appendingPathComponent("broken", isDirectory: true),
            withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "x".write(to: good.appendingPathComponent("hosts"), atomically: true, encoding: .utf8)
        try makeUnreadableDirectory(at: root.appendingPathComponent("broken/etc"))

        let stack = try XCTUnwrap(
            LayeredRootFS(layers: [
                root.appendingPathComponent("good", isDirectory: true),
                root.appendingPathComponent("broken", isDirectory: true),
            ]))
        let listing = stack.listDirectory(relativePath: "etc", showHiddenFiles: false)

        XCTAssertEqual(listing.entries.map(\.name), ["hosts"])
        // Identify *which* layer failed: a caller browsing several
        // directories unions these, and a bare count would collapse
        // failures in different layers into one.
        XCTAssertEqual(listing.excludedLayers, [1])
    }

    func testDistinctDirectoriesReportDistinctFailingLayers() throws {
        // The case a bare count loses: /etc fails on one layer and /opt on
        // another, so a caller unioning these sees two layers with holes,
        // not one.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let a = root.appendingPathComponent("a", isDirectory: true)
        let b = root.appendingPathComponent("b", isDirectory: true)
        try FileManager.default.createDirectory(
            at: a.appendingPathComponent("opt"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(
            at: b.appendingPathComponent("etc"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // Each layer has one directory that exists but cannot be listed.
        try makeUnreadableDirectory(at: a.appendingPathComponent("etc"))
        try makeUnreadableDirectory(at: b.appendingPathComponent("opt"))

        let stack = try XCTUnwrap(LayeredRootFS(layers: [a, b]))

        XCTAssertEqual(
            stack.listDirectory(relativePath: "etc", showHiddenFiles: false).excludedLayers, [0, 1])
        XCTAssertEqual(
            stack.listDirectory(relativePath: "opt", showHiddenFiles: false).excludedLayers, [1])
    }

    func testUnreadableUpperLayerHidesLowerEntriesRatherThanShowingStaleOnes() throws {
        // The upper layer decides what the lower one is allowed to show: it
        // can replace a file or whiteout it entirely. If it cannot be read,
        // surfacing the lower layer's copy would show content the container
        // does not actually have — worse than showing nothing. The stack
        // truncates at the failure instead.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let upper = root.appendingPathComponent("upper", isDirectory: true)
        let lower = root.appendingPathComponent("lower/etc", isDirectory: true)
        try FileManager.default.createDirectory(at: upper, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: lower, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        // `etc` exists in the upper layer but will not list.
        try makeUnreadableDirectory(at: upper.appendingPathComponent("etc"))
        try "stale".write(
            to: lower.appendingPathComponent("passwd"), atomically: true, encoding: .utf8)

        let stack = try XCTUnwrap(
            LayeredRootFS(layers: [upper, root.appendingPathComponent("lower", isDirectory: true)]))
        let listing = stack.listDirectory(relativePath: "etc", showHiddenFiles: false)

        XCTAssertEqual(listing.entries.map(\.name), [])
        XCTAssertEqual(listing.excludedLayers, [0, 1])
    }

    func testLayersAboveAnUnreadableOneStillMerge() throws {
        // Precedence runs downward, so nothing below can override what the
        // readable top layers already decided — those entries stay sound.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let top = root.appendingPathComponent("top/etc", isDirectory: true)
        let mid = root.appendingPathComponent("mid", isDirectory: true)
        let bottom = root.appendingPathComponent("bottom/etc", isDirectory: true)
        for dir in [top, mid, bottom] {
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: root) }

        try "top".write(to: top.appendingPathComponent("hosts"), atomically: true, encoding: .utf8)
        try makeUnreadableDirectory(at: mid.appendingPathComponent("etc"))
        try "bottom".write(
            to: bottom.appendingPathComponent("resolv.conf"), atomically: true, encoding: .utf8)

        let stack = try XCTUnwrap(
            LayeredRootFS(layers: [
                root.appendingPathComponent("top", isDirectory: true),
                mid,
                root.appendingPathComponent("bottom", isDirectory: true),
            ]))
        let listing = stack.listDirectory(relativePath: "etc", showHiddenFiles: false)

        XCTAssertEqual(listing.entries.map(\.name), ["hosts"])
        XCTAssertEqual(listing.excludedLayers, [1, 2])
    }

    // MARK: host-layer resolution

    func testResolveHostLayersTruncatesAtAnUnmappableLayer() throws {
        // An unmappable upper layer still decides what the layers beneath it
        // may show, so dropping it and keeping the lower ones would surface
        // files it may have replaced or deleted. The lower layer is present in
        // the export, so only truncation can keep it out of the result.
        let export = try makeGuestExport(containing: ["volumes"])
        let resolution = LayeredRootFS.resolveHostLayers(
            guestPaths: [
                "/somewhere/else/upper",
                "/var/lib/docker/volumes",
            ], exportRoot: export)

        XCTAssertEqual(resolution.hostURLs, [])
        XCTAssertEqual(resolution.excludedCount, 2)
    }

    func testResolveHostLayersTruncatesAtAMissingLayer() throws {
        // Same rule when the path maps fine but is not on the host: the
        // layer is unavailable, and what it deletes is unknowable.
        let export = try makeGuestExport(containing: ["volumes"])
        let resolution = LayeredRootFS.resolveHostLayers(
            guestPaths: [
                "/var/lib/docker/definitely-not-present-\(UUID().uuidString)",
                "/var/lib/docker/volumes",
            ], exportRoot: export)

        XCTAssertEqual(resolution.hostURLs, [])
        XCTAssertEqual(resolution.excludedCount, 2)
    }

    func testMissingLayerDirectoryTruncatesTheMerge() throws {
        // A layer whose directory is gone entirely is unavailable — distinct
        // from a present layer that merely lacks the path, which is normal
        // and must keep merging.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let present = root.appendingPathComponent("present/etc", isDirectory: true)
        let lower = root.appendingPathComponent("lower/etc", isDirectory: true)
        try FileManager.default.createDirectory(at: present, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: lower, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try "x".write(to: lower.appendingPathComponent("passwd"), atomically: true, encoding: .utf8)

        let stack = try XCTUnwrap(
            LayeredRootFS(layers: [
                root.appendingPathComponent("present", isDirectory: true),
                root.appendingPathComponent("gone", isDirectory: true),
                root.appendingPathComponent("lower", isDirectory: true),
            ]))
        let listing = stack.listDirectory(relativePath: "etc", showHiddenFiles: false)

        XCTAssertEqual(listing.entries.map(\.name), [])
        XCTAssertEqual(listing.excludedLayers, [1, 2])
    }

    func testResolveHostLayersCanTruncateToASingleSurvivor() throws {
        // The case the badge used to go silent on: the stack collapses to one
        // browsable layer, so there is no composed stack left to hang a
        // warning off — but four fifths of the filesystem is missing.
        let export = try makeGuestExport(containing: ["volumes"])
        let resolution = LayeredRootFS.resolveHostLayers(
            guestPaths: [
                "/var/lib/docker/volumes",
                "/somewhere/else/layer1",
                "/somewhere/else/layer2",
            ], exportRoot: export)

        XCTAssertEqual(resolution.hostURLs.count, 1)
        XCTAssertEqual(resolution.excludedCount, 2)
    }

    func testBadgeLabelReportsPartialMerges() {
        XCTAssertEqual(LayerMergeBadge.label(total: 5, unavailable: 0), "merged from 5 layers")
        XCTAssertEqual(
            LayerMergeBadge.label(total: 5, unavailable: 4), "merged from 1 of 5 layers")
    }

    // MARK: browsing composition

    func testExpandingAMergedDirectoryMergesAcrossEveryLayer() throws {
        // The seam the outline depends on and nothing covered: a directory
        // node carries the URL of whichever layer won it, so expanding it has
        // to go back through the stack rather than list that layer alone.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let upper = root.appendingPathComponent("upper/etc", isDirectory: true)
        let lower = root.appendingPathComponent("lower/etc", isDirectory: true)
        try FileManager.default.createDirectory(at: upper, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: lower, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "u".write(to: upper.appendingPathComponent("hosts"), atomically: true, encoding: .utf8)
        try "l".write(
            to: lower.appendingPathComponent("resolv.conf"), atomically: true, encoding: .utf8)

        let stack = try XCTUnwrap(
            LayeredRootFS(layers: [
                root.appendingPathComponent("upper", isDirectory: true),
                root.appendingPathComponent("lower", isDirectory: true),
            ]))

        let rootListing = stack.listDirectory(relativePath: "", showHiddenFiles: false)
        let etc = try XCTUnwrap(rootListing.entries.first { $0.name == "etc" })
        // `etc` was won by the upper layer, whose copy holds only `hosts`.
        let relativePath = try XCTUnwrap(stack.relativePath(forHostURL: etc.url))
        let children = stack.listDirectory(relativePath: relativePath, showHiddenFiles: false)

        XCTAssertEqual(relativePath, "etc")
        XCTAssertEqual(children.entries.map(\.name), ["hosts", "resolv.conf"])
    }

    func testNonDirectoryInALowerLayerIsShadowedWithoutWarning() throws {
        // An upper directory over a lower file is ordinary overlay shadowing:
        // the merge stops there because the file hides everything beneath it,
        // and reporting that as an excluded layer would cry wolf.
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        let upperFoo = root.appendingPathComponent("upper/foo", isDirectory: true)
        let lower = root.appendingPathComponent("lower", isDirectory: true)
        try FileManager.default.createDirectory(at: upperFoo, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: lower, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }

        try "u".write(to: upperFoo.appendingPathComponent("inside"), atomically: true, encoding: .utf8)
        try "shadowed".write(
            to: lower.appendingPathComponent("foo"), atomically: true, encoding: .utf8)

        let stack = try XCTUnwrap(
            LayeredRootFS(layers: [
                root.appendingPathComponent("upper", isDirectory: true), lower,
            ]))
        let listing = stack.listDirectory(relativePath: "foo", showHiddenFiles: false)

        XCTAssertEqual(listing.entries.map(\.name), ["inside"])
        XCTAssertEqual(listing.excludedLayers, [])
    }
}
