import ArcBoxClient
import XCTest

@testable import ArcBox

@MainActor
final class DaemonRegistrationFailureTests: XCTestCase {
    private let epermIsh = NSError(
        domain: "SMAppServiceErrorDomain", code: 1,
        userInfo: [NSLocalizedDescriptionKey: "Operation not permitted"])

    /// "Operation not permitted" fits several unrelated causes, and the domain and code
    /// are what separate them — in the message and in the crash reporter's grouping.
    func testTheMessageCarriesTheDomainAndCode() {
        let message = DaemonManager.registrationFailure(epermIsh)

        XCTAssertTrue(message.contains("Operation not permitted"), message)
        XCTAssertTrue(message.contains("[SMAppServiceErrorDomain 1]"), message)
    }

    /// The one cause we can identify outright. `abctl _install` bootstraps a plist for the
    /// same label into ~/Library/LaunchAgents, and SMAppService then cannot register the
    /// bundled copy — a state the user has to undo by hand, so the message has to say so.
    func testAConflictingLaunchAgentIsNamedWhenOneExists() throws {
        let agents = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
        let planted = agents.appendingPathComponent(DaemonManager.daemonPlistName)
        try XCTSkipIf(
            FileManager.default.fileExists(atPath: planted.path),
            "a real conflicting agent is installed; refusing to touch it")

        try FileManager.default.createDirectory(at: agents, withIntermediateDirectories: true)
        try Data("<plist/>".utf8).write(to: planted)
        defer { try? FileManager.default.removeItem(at: planted) }

        let message = DaemonManager.registrationFailure(epermIsh)

        XCTAssertTrue(message.contains(planted.path), message)
        XCTAssertTrue(message.contains("abctl _uninstall"), message)
    }

    func testNothingIsBlamedWhenNoAgentIsInstalled() throws {
        let planted = FileManager.default.homeDirectoryForCurrentUser
            .appendingPathComponent("Library/LaunchAgents", isDirectory: true)
            .appendingPathComponent(DaemonManager.daemonPlistName)
        try XCTSkipIf(FileManager.default.fileExists(atPath: planted.path), "a real agent is installed")

        let message = DaemonManager.registrationFailure(epermIsh)

        XCTAssertFalse(message.contains("abctl _uninstall"), message)
        XCTAssertTrue(message.hasPrefix("Failed to register daemon:"), message)
    }
}
