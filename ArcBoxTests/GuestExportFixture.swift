import Foundation
import XCTest

extension XCTestCase {
    /// Builds a throwaway stand-in for the `~/ArcBox/docker` export containing the
    /// given layer directories.
    ///
    /// Layer resolution maps a guest path onto the export and then stats it, so
    /// tests that need a layer to *resolve* would otherwise only pass on a
    /// machine where the daemon is running and the export is mounted. Pointing
    /// resolution at a directory the test owns keeps the rules under test —
    /// truncation, exclusion counting — and drops the host dependency.
    ///
    /// The directory is removed when the test finishes.
    func makeGuestExport(
        containing layers: [String] = [],
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws -> URL {
        let root = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }

        for layer in layers {
            try FileManager.default.createDirectory(
                at: root.appendingPathComponent(layer, isDirectory: true),
                withIntermediateDirectories: true)
        }
        return root
    }
}
