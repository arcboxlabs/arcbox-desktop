import Foundation

struct LocalFileEntry: Identifiable, Hashable {
    let url: URL
    let name: String
    let isDirectory: Bool
    let isPackage: Bool
    let isSymbolicLink: Bool
    let sizeBytes: Int64?
    let modifiedDate: Date?
    let kind: String
    var children: [LocalFileEntry]?
    var loadError: String?

    var id: String { url.standardizedFileURL.path }
    var isExpandable: Bool { isDirectory && !isPackage }

    var sizeDisplay: String {
        guard let sizeBytes else { return "" }
        return ByteCountFormatter.string(fromByteCount: sizeBytes, countStyle: .file)
    }

    var dateDisplay: String {
        guard let modifiedDate else { return "" }
        return LocalRootFSService.modifiedDateFormatter.string(from: modifiedDate)
    }
}

struct LocalRootFSService {
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

    static let modifiedDateFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .medium
        formatter.timeStyle = .short
        return formatter
    }()

    private static let resourceKeys: Set<URLResourceKey> = [
        .isDirectoryKey,
        .isPackageKey,
        .isSymbolicLinkKey,
        .isHiddenKey,
        .fileSizeKey,
        .contentModificationDateKey,
        .localizedTypeDescriptionKey,
        .nameKey,
    ]

    func resolveRootURL(path: String?) throws -> URL {
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

    func listDirectory(at directoryURL: URL, showHiddenFiles: Bool) throws -> [LocalFileEntry] {
        var coordinatorError: NSError?
        var capturedError: Error?
        var entries: [LocalFileEntry] = []

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
                    let isPackage = values.isPackage ?? false
                    let kind: String
                    if isDirectory && !isPackage {
                        kind = "Folder"
                    } else {
                        kind = values.localizedTypeDescription ?? "Document"
                    }

                    return LocalFileEntry(
                        url: entryURL,
                        name: values.name ?? entryURL.lastPathComponent,
                        isDirectory: isDirectory,
                        isPackage: isPackage,
                        isSymbolicLink: values.isSymbolicLink ?? false,
                        sizeBytes: isDirectory ? nil : Int64(values.fileSize ?? 0),
                        modifiedDate: values.contentModificationDate,
                        kind: kind,
                        children: nil,
                        loadError: nil
                    )
                }
                .sorted {
                    $0.name.localizedStandardCompare($1.name) == .orderedAscending
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
