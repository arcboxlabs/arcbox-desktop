import Foundation
import os

/// Browses an overlay layer stack as one merged filesystem.
///
/// Containers and images under the containerd image store are not a single
/// directory: the daemon resolves them to the same layer list the kernel
/// would mount — a writable upper layer (containers only) followed by the
/// image layers, highest first. The read-only `~/ArcBox/docker` export serves each
/// layer directory separately, so composing them here is what turns "the
/// container's own writes" into "the container's filesystem".
///
/// This is a client-side union, not an overlayfs mount, and it reproduces
/// overlay precedence and whiteouts but not opaque directories: those are
/// recorded in a `trusted.overlay.*` xattr that does not survive the NFS
/// export, so a directory the upper layer replaced wholesale still shows the
/// entries it shadowed. A kernel-composed view (ABX-424) removes that caveat.
nonisolated struct LayeredRootFS {
    /// Layer directories, highest precedence first — the order overlayfs
    /// encodes as `upperdir` then `lowerdir=A:B:C`.
    let layers: [URL]

    init?(layers: [URL]) {
        guard !layers.isEmpty else { return nil }
        self.layers = layers
    }

    /// The merged contents of one directory, plus which layers are missing
    /// from it.
    struct Listing {
        let entries: [LocalFileEntry]
        /// Indices into `layers` whose content is not represented in
        /// `entries`: the layer that failed to list, and — because its
        /// whiteouts and replacements are unknowable — everything beneath
        /// it. A caller showing this listing must be able to say it is
        /// incomplete; identifying *which* layers lets callers union
        /// failures across directories instead of undercounting them.
        let excludedLayers: Set<Int>
    }

    /// Lists the merged contents of a directory given relative to the stack
    /// root.
    ///
    /// A layer that cannot be read truncates the stack rather than being
    /// skipped over. Skipping would let entries from lower layers surface
    /// even though the unreadable layer may delete or replace them — showing
    /// files the container or image does not actually have, which is worse
    /// than showing fewer. Everything *above* the failure is unaffected:
    /// lower layers can never override it. So the listing stays sound and
    /// merely loses depth, and the loss is reported.
    func listDirectory(relativePath: String, showHiddenFiles: Bool) -> Listing {
        var listings: [[LocalRootFSService.LayerItem]] = []
        var excluded: Set<Int> = []

        let readings = readLayers(relativePath: relativePath, showHiddenFiles: showHiddenFiles)

        for (index, layer) in layers.enumerated() {
            let directory = Self.resolve(relativePath, in: layer)
            do {
                listings.append(try readings[index].get())
            } catch {
                switch Self.fileType(of: directory) {
                case nil where Self.fileType(of: layer) != nil:
                    // The layer is present but simply lacks this path, so it
                    // holds no opinion about it — a whiteout would have to
                    // live inside that very directory. Normal; keep merging.
                    continue
                case .some(let type) where type != S_IFDIR:
                    // A non-directory shadows everything below it, exactly as
                    // the kernel would stop merging here. The listing is
                    // complete, so this is not a gap to report.
                    return Listing(entries: Self.merge(listings), excludedLayers: excluded)
                default:
                    // Either the layer is gone outright or the directory is
                    // there and will not open. Both leave whiteouts and
                    // replacements unknowable, so nothing below can be shown.
                    Log.container.error(
                        """
                        layer \(index, privacy: .public) excluded from merge: \
                        \(error.localizedDescription, privacy: .private)
                        """
                    )
                    excluded.formUnion(index..<layers.count)
                }
                break
            }
        }

        return Listing(entries: Self.merge(listings), excludedLayers: excluded)
    }

    /// Reads the same relative directory from every layer at once.
    ///
    /// The listings are independent, and each is a round trip to the guest
    /// over NFS, so reading them in sequence would make one directory expand
    /// cost the stack depth in latency. Ordering is preserved by index, and
    /// [`listDirectory`] still consumes the results top-down, so truncation
    /// behaves exactly as it would have sequentially — the only difference is
    /// that a truncated tail was fetched and then discarded, which is the
    /// rare path.
    private func readLayers(
        relativePath: String,
        showHiddenFiles: Bool
    ) -> [Result<[LocalRootFSService.LayerItem], Error>] {
        let lock = NSLock()
        var readings: [Int: Result<[LocalRootFSService.LayerItem], Error>] = [:]

        DispatchQueue.concurrentPerform(iterations: layers.count) { index in
            let directory = Self.resolve(relativePath, in: layers[index])
            let reading = Result {
                try LocalRootFSService.listLayerItems(
                    at: directory, showHiddenFiles: showHiddenFiles)
            }
            lock.lock()
            readings[index] = reading
            lock.unlock()
        }

        return layers.indices.map { readings[$0]! }
    }

    /// Layer paths mapped onto the export, and how many were left behind.
    struct Resolution {
        /// Host URLs for the layers that can be browsed, highest first.
        let hostURLs: [URL]
        /// Layers dropped from the tail, either unmappable or absent on the
        /// host. Never represented in the merge, so a caller must count them
        /// against the view's completeness.
        let excludedCount: Int
    }

    /// Maps daemon-reported guest layer paths onto the `~/ArcBox/docker` export,
    /// stopping at the first layer the host cannot browse.
    ///
    /// Truncating rather than dropping matters for the same reason it does
    /// inside [`listDirectory`]: a layer that cannot be browsed still decides
    /// what the layers beneath it may show, so merging past it would surface
    /// entries it may replace or delete.
    static func resolveHostLayers(
        guestPaths: [String], exportRoot: URL = GuestDataMount.rootURL
    ) -> Resolution {
        var hostURLs: [URL] = []
        for guestPath in guestPaths {
            // Hand back what the check produced: callers would otherwise
            // repeat the same existence check to standardize the URL, and on
            // a wedged export that check blocks.
            guard let hostURL = GuestDataMount.hostURL(forGuestPath: guestPath, exportRoot: exportRoot),
                let resolved = try? LocalRootFSService.resolveRootURL(path: hostURL.path)
            else {
                break
            }
            hostURLs.append(resolved)
        }
        return Resolution(
            hostURLs: hostURLs,
            excludedCount: guestPaths.count - hostURLs.count
        )
    }

    /// Maps a host URL that came out of [`listDirectory`] back to its path
    /// relative to the stack root, so expanding a node can re-merge across
    /// every layer rather than only the one the node happened to come from.
    func relativePath(forHostURL url: URL) -> String? {
        let path = url.standardizedFileURL.path
        for layer in layers {
            let base = layer.standardizedFileURL.path
            if path == base {
                return ""
            }
            if path.hasPrefix(base + "/") {
                return String(path.dropFirst(base.count + 1))
            }
        }
        return nil
    }

    /// Merges per-layer listings, highest layer first.
    ///
    /// The first layer to name an entry decides it: a regular entry is taken
    /// as-is, a whiteout deletes the name for every layer below (and is
    /// itself hidden, being overlay bookkeeping rather than content).
    static func merge(_ listings: [[LocalRootFSService.LayerItem]]) -> [LocalFileEntry] {
        var decided: Set<String> = []
        var merged: [LocalFileEntry] = []

        for listing in listings {
            for item in listing {
                guard decided.insert(item.entry.name).inserted else { continue }
                if !item.isWhiteout {
                    merged.append(item.entry)
                }
            }
        }

        return merged.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    private static func resolve(_ relativePath: String, in layer: URL) -> URL {
        relativePath.isEmpty ? layer : layer.appending(path: relativePath, directoryHint: .inferFromPath)
    }

    /// The `S_IFMT` bits at `url`, or `nil` if nothing is there.
    ///
    /// Deliberately `lstat`: a symlink is a non-directory to overlayfs and
    /// shadows lower layers, and following it here would merge past it.
    private static func fileType(of url: URL) -> mode_t? {
        var status = stat()
        guard lstat(url.path, &status) == 0 else { return nil }
        return status.st_mode & S_IFMT
    }
}
