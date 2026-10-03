import Foundation

nonisolated struct LocalFileEntry: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let isSymbolicLink: Bool
    let sizeBytes: Int64?
    let modifiedDate: Date?
    let kind: String
    var children: [LocalFileEntry]?
    var loadError: String?

    var id: String { url.standardizedFileURL.path }
    var isExpandable: Bool { isDirectory }

    var systemImageName: String {
        switch kind {
        case "Directory": "folder"
        case "Symlink": "link"
        case "Executable": "terminal"
        default: "doc"
        }
    }

    var sizeDisplay: String {
        guard let sizeBytes else { return "" }
        return formattedBytes(sizeBytes)
    }

    @MainActor var dateDisplay: String {
        guard let modifiedDate else { return "" }
        return LocalRootFSService.modifiedDateFormatter.string(from: modifiedDate)
    }
}

nonisolated struct LocalRootFSService {
    enum RootFSError: LocalizedError {
        case missingRootPath
        case pathNotFound(String)
        case notDirectory(String)

        var errorDescription: String? {
            switch self {
            case .missingRootPath:
                return "Container has no configured rootfs mount path."
            case .pathNotFound(let path):
                return "Rootfs path does not exist: \(path)"
            case .notDirectory(let path):
                return "Rootfs path is not a directory: \(path)"
            }
        }
    }

    @MainActor static let modifiedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isSymbolicLinkKey,
        .isHiddenKey,
        .fileSizeKey,
        .contentModificationDateKey,
        .fileResourceTypeKey,
        .nameKey,
    ]

    /// One directory entry as read from a single layer, carrying the overlay
    /// bookkeeping that [`LayeredRootFS`] needs but a plain listing does not.
    struct LayerItem {
        let entry: LocalFileEntry
        /// Overlayfs marks a file deleted in an upper layer with a character
        /// device of rdev 0:0 under the deleted name.
        let isWhiteout: Bool
    }

    /// Whether an entry is an overlay whiteout — a character device of
    /// rdev 0:0 standing in for a name deleted in a lower layer.
    ///
    /// The device number is what separates bookkeeping from content: layers
    /// legitimately carry character devices (an image shipping `/dev/null`,
    /// a privileged container's own nodes), and classifying those as
    /// deletions would hide both the device and whatever it shadows below.
    /// Only character devices are stat'd, so the common entry pays nothing.
    static func isWhiteout(_ url: URL, resourceType: URLFileResourceType?) -> Bool {
        guard resourceType == .characterSpecial else { return false }
        var status = stat()
        guard lstat(url.path, &status) == 0 else { return false }
        return status.st_rdev == 0
    }

    static func resolveRootURL(path: String?) throws -> URL {
        guard let rawPath = path?.trimmingCharacters(in: .whitespacesAndNewlines), !rawPath.isEmpty else {
            throw RootFSError.missingRootPath
        }

        let rootURL = URL(fileURLWithPath: rawPath, isDirectory: true)
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory) else {
            throw RootFSError.pathNotFound(rootURL.path)
        }
        guard isDirectory.boolValue else {
            throw RootFSError.notDirectory(rootURL.path)
        }

        return rootURL.standardizedFileURL
    }

    static func listDirectory(at directoryURL: URL, showHiddenFiles: Bool) throws -> [LocalFileEntry] {
        try listLayerItems(at: directoryURL, showHiddenFiles: showHiddenFiles)
            .map(\.entry)
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// Lists a directory keeping the overlay whiteout marker, so a layered
    /// browse can hide both the marker and whatever it deletes underneath.
    ///
    /// Unordered: a merge across layers has to sort the union anyway, and
    /// sorting each layer first would be work thrown away.
    static func listLayerItems(at directoryURL: URL, showHiddenFiles: Bool) throws -> [LayerItem] {
        var coordinatorError: NSError?
        var capturedError: Error?
        var entries: [LayerItem] = []

        let coordinator = NSFileCoordinator(filePresenter: nil)
        coordinator.coordinate(readingItemAt: directoryURL, options: .withoutChanges, error: &coordinatorError) {
            coordinatedURL in
            do {
                var options: FileManager.DirectoryEnumerationOptions = [.skipsPackageDescendants]
                if !showHiddenFiles {
                    options.insert(.skipsHiddenFiles)
                }

                let urls = try FileManager.default.contentsOfDirectory(
                    at: coordinatedURL,
                    includingPropertiesForKeys: Array(Self.resourceKeys),
                    options: options
                )

                entries = try urls.compactMap { entryURL in
                    let values = try entryURL.resourceValues(forKeys: Self.resourceKeys)
                    if !showHiddenFiles && values.isHidden == true {
                        return nil
                    }

                    let isDirectory = values.isDirectory ?? false
                    let isSymbolicLink = values.isSymbolicLink ?? false
                    let kind = neutralKind(
                        at: entryURL,
                        isDirectory: isDirectory,
                        isSymbolicLink: isSymbolicLink
                    )

                    let entry = LocalFileEntry(
                        url: entryURL,
                        name: values.name ?? entryURL.lastPathComponent,
                        isDirectory: isDirectory,
                        isSymbolicLink: isSymbolicLink,
                        sizeBytes: isDirectory ? nil : Int64(values.fileSize ?? 0),
                        modifiedDate: values.contentModificationDate,
                        kind: kind,
                        children: nil,
                        loadError: nil
                    )
                    return LayerItem(
                        entry: entry,
                        isWhiteout: isWhiteout(entryURL, resourceType: values.fileResourceType)
                    )
                }
            } catch {
                capturedError = error
            }
        }

        if let coordinatorError {
            throw coordinatorError
        }
        if let capturedError {
            throw capturedError
        }

        return entries
    }

    private static func neutralKind(
        at url: URL,
        isDirectory: Bool,
        isSymbolicLink: Bool
    ) -> String {
        if isSymbolicLink { return "Symlink" }
        if isDirectory { return "Directory" }

        var status = stat()
        guard lstat(url.path, &status) == 0, status.st_mode & 0o111 != 0 else {
            return "File"
        }
        return "Executable"
    }

    static func finderDefaultShowHiddenFiles() -> Bool {
        guard let finderDefaults = UserDefaults(suiteName: "com.apple.finder") else {
            return false
        }

        if let boolValue = finderDefaults.object(forKey: "AppleShowAllFiles") as? Bool {
            return boolValue
        }

        if let stringValue = finderDefaults.string(forKey: "AppleShowAllFiles") {
            return ["1", "true", "yes"].contains(stringValue.lowercased())
        }

        return false
    }
}
