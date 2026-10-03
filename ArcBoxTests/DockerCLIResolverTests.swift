import XCTest

@testable import ArcBox

final class DockerCLIResolverTests: XCTestCase {
    private var root: URL!

    override func setUpWithError() throws {
        root = FileManager.default.temporaryDirectory.appendingPathComponent("docker-cli-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try FileManager.default.removeItem(at: root)
    }

    /// A directory holding a `docker` file with the given mode.
    private func binDirectory(named name: String, dockerMode: Int) throws -> String {
        let directory = root.appendingPathComponent(name)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let docker = directory.appendingPathComponent("docker").path
        try Data("#!/bin/sh\n".utf8).write(to: URL(fileURLWithPath: docker))
        try FileManager.default.setAttributes([.posixPermissions: dockerMode], ofItemAtPath: docker)
        return directory.path
    }

    func testTheFirstExecutableOnThePathWins() throws {
        let notExecutable = try binDirectory(named: "a", dockerMode: 0o644)
        let first = try binDirectory(named: "b", dockerMode: 0o755)
        let second = try binDirectory(named: "c", dockerMode: 0o755)
        let empty = root.appendingPathComponent("d").path

        let found = DockerCLIResolver.executable(
            named: "docker", onPath: "\(empty):\(notExecutable)::\(first):\(second)")

        XCTAssertEqual(found, "\(first)/docker")
    }

    func testNoExecutableOnThePathIsNil() throws {
        let notExecutable = try binDirectory(named: "a", dockerMode: 0o644)

        XCTAssertNil(DockerCLIResolver.executable(named: "docker", onPath: notExecutable))
        XCTAssertNil(DockerCLIResolver.executable(named: "docker", onPath: ""))
    }
}
