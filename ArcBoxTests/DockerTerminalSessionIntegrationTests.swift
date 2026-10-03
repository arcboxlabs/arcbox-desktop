import SwiftTerm
import XCTest

@testable import ArcBox

final class DockerTerminalSessionIntegrationTests: XCTestCase {
    private struct CommandResult {
        let status: Int32
        let output: String
    }

    private var dockerPath: String?
    private var dockerHost: String?
    private var cleanupContainerNames: [String] = []
    private var cleanupVolumeNames: [String] = []

    override func tearDownWithError() throws {
        defer {
            dockerPath = nil
            dockerHost = nil
            cleanupContainerNames = []
            cleanupVolumeNames = []
        }

        for name in cleanupContainerNames {
            let result = try docker(["container", "rm", "--force", "--volumes", name])
            if result.status != 0, !result.output.contains("No such container") {
                XCTFail("Failed to remove integration container \(name): \(result.output)")
            }
        }
        for name in cleanupVolumeNames {
            let result = try docker(["volume", "rm", "--force", name])
            if result.status != 0, !result.output.contains("No such volume") {
                XCTFail("Failed to remove integration volume \(name): \(result.output)")
            }
        }
    }

    @MainActor
    func testReplacingAndDisconnectingImageSessionRemovesContainersAndAnonymousVolumes() async throws {
        try requireDockerWithPostgresImage()

        let terminalView = TerminalView(frame: .zero)
        terminalView.resize(cols: 80, rows: 24)
        let session = DockerTerminalSession()

        session.runImage(imageName: "postgres:18", shell: "/bin/sh", terminalView: terminalView)
        let firstContainer = try XCTUnwrap(session.activeImageContainerName)
        cleanupContainerNames.append(firstContainer)
        let firstVolumes = try await anonymousVolumes(whenContainerAppears: firstContainer)
        cleanupVolumeNames.append(contentsOf: firstVolumes)

        let trapCommand = Data(
            "trap 'printf \"OLD-%s\\n\" \"SESSION\"' TERM; printf \"TRAP-%s\\n\" \"READY\"\r".utf8
        )
        let trapReady = try await eventually {
            let output = String(bytes: terminalView.getTerminal().getBufferAsData(), encoding: .utf8)
            if output?.contains("TRAP-READY") == true { return true }
            session.send(trapCommand)
            return false
        }
        XCTAssertTrue(trapReady, "Image terminal never installed its TERM trap")
        terminalView.getTerminal().resetToInitialState()

        session.runImage(imageName: "postgres:18", shell: "/bin/sh", terminalView: terminalView)
        let secondContainer = try XCTUnwrap(session.activeImageContainerName)
        cleanupContainerNames.append(secondContainer)
        let secondVolumes = try await anonymousVolumes(whenContainerAppears: secondContainer)
        cleanupVolumeNames.append(contentsOf: secondVolumes)

        try await assertRemoved(container: firstContainer, volumes: firstVolumes)

        let newShellReadyProbe = Data("printf \"NEW-%s\\n\" \"READY\"\r".utf8)
        let newShellReady = try await eventually {
            let output = String(bytes: terminalView.getTerminal().getBufferAsData(), encoding: .utf8)
            if output?.contains("NEW-READY") == true { return true }
            session.send(newShellReadyProbe)
            return false
        }
        XCTAssertTrue(newShellReady, "Replacement image terminal shell never became ready")

        let outputAfterReplacement = try XCTUnwrap(
            String(bytes: terminalView.getTerminal().getBufferAsData(), encoding: .utf8)
        )
        XCTAssertFalse(
            outputAfterReplacement.contains("OLD-SESSION"),
            "Old image terminal output appeared after replacement"
        )

        session.disconnect()

        try await assertRemoved(container: secondContainer, volumes: secondVolumes)
    }

    @MainActor
    func testImmediateDisconnectDoesNotLeaveALatePublishedContainer() async throws {
        try requireDockerWithPostgresImage()

        let session = DockerTerminalSession()
        session.runImage(imageName: "postgres:18", shell: "/bin/sh", terminalView: TerminalView(frame: .zero))
        let container = try XCTUnwrap(session.activeImageContainerName)
        cleanupContainerNames.append(container)

        session.disconnect()

        try await Task.sleep(for: .seconds(2))
        let result = try docker(["container", "inspect", "--format", "{{.Id}}", container])
        XCTAssertNotEqual(result.status, 0, "Immediate disconnect left image terminal container \(container)")
    }

    @MainActor
    private func requireDockerWithPostgresImage() throws {
        guard let path = DockerCLIResolver.findDockerCLI() else {
            throw XCTSkip("ABXD-137 integration requires a local Docker CLI")
        }
        dockerPath = path

        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let profile = Bundle.main.object(forInfoDictionaryKey: "ArcBoxProfile") as? String
        let dataDirectory =
            profile?.caseInsensitiveCompare("development") == .orderedSame ? ".arcbox-dev" : ".arcbox"
        let host = "unix://\(home)/\(dataDirectory)/run/docker.sock"
        dockerHost = host

        let info = try docker(["version", "--format", "{{.Server.Version}}"])
        guard info.status == 0 else {
            throw XCTSkip("ABXD-137 integration requires the ArcBox Docker engine at \(host)")
        }

        let image = try docker(["image", "inspect", "--format", "{{.Id}}", "postgres:18"])
        guard image.status == 0 else {
            throw XCTSkip("ABXD-137 integration requires the existing postgres:18 image; the test never pulls images")
        }
    }

    @MainActor
    private func anonymousVolumes(whenContainerAppears name: String) async throws -> [String] {
        let appeared = try await eventually {
            try docker(["container", "inspect", "--format", "{{.Id}}", name]).status == 0
        }
        XCTAssertTrue(appeared, "Image terminal container \(name) never appeared")

        let result = try docker([
            "container", "inspect", "--format",
            "{{range .Mounts}}{{if eq .Type \"volume\"}}{{println .Name}}{{end}}{{end}}", name,
        ])
        XCTAssertEqual(result.status, 0, result.output)
        let volumes = result.output.split(whereSeparator: \.isNewline).map(String.init)
        XCTAssertFalse(volumes.isEmpty, "postgres:18 should create an anonymous data volume")
        return volumes
    }

    @MainActor
    private func assertRemoved(container: String, volumes: [String]) async throws {
        let containerRemoved = try await eventually {
            try docker(["container", "inspect", "--format", "{{.Id}}", container]).status != 0
        }
        XCTAssertTrue(containerRemoved, "Image terminal container \(container) still exists after disconnect")

        for volume in volumes {
            let volumeRemoved = try await eventually {
                try docker(["volume", "inspect", "--format", "{{.Name}}", volume]).status != 0
            }
            XCTAssertTrue(volumeRemoved, "Anonymous volume \(volume) still exists after disconnect")
        }
    }

    @MainActor
    private func eventually(
        timeout: TimeInterval = 10,
        condition: () throws -> Bool
    ) async throws -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if try condition() { return true }
            try await Task.sleep(for: .milliseconds(200))
        } while Date() < deadline
        return false
    }

    private func docker(_ arguments: [String]) throws -> CommandResult {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: try XCTUnwrap(dockerPath))
        process.arguments = ["--host", try XCTUnwrap(dockerHost)] + arguments

        let output = Pipe()
        process.standardOutput = output
        process.standardError = output

        try process.run()
        process.waitUntilExit()
        let data = output.fileHandleForReading.readDataToEndOfFile()
        return CommandResult(
            status: process.terminationStatus,
            output: try XCTUnwrap(String(data: data, encoding: .utf8))
                .trimmingCharacters(in: .whitespacesAndNewlines)
        )
    }
}
