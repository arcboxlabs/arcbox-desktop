import Sentry
import XCTest

@testable import ArcBox

@MainActor
final class ErrorReportingScrubTests: XCTestCase {
    private var home: String { FileManager.default.homeDirectoryForCurrentUser.path }

    /// The leak this guards: a daemon error quoting its own absolute path put the user's
    /// account name in the issue title, where breadcrumb-only scrubbing never reached it.
    func testAnExceptionValueLosesTheHomeDirectory() throws {
        let event = Event()
        let exception = Exception(
            value: "Failed to open \(home)/.arcbox/data/docker.img: No such file or directory",
            type: "StartupError")
        event.exceptions = [exception]

        AppDelegate.scrubPII(event)

        let value = try XCTUnwrap(event.exceptions?.first?.value)
        XCTAssertEqual(value, "Failed to open ~/.arcbox/data/docker.img: No such file or directory")
        XCTAssertFalse(value.contains(home))
    }

    func testBreadcrumbsAndTheMessageAreScrubbedToo() throws {
        let event = Event()
        let crumb = Breadcrumb()
        crumb.message = "reading \(home)/.arcbox/config.toml"
        event.breadcrumbs = [crumb]
        event.message = SentryMessage(formatted: "starting from \(home)/.arcbox")

        AppDelegate.scrubPII(event)

        XCTAssertEqual(event.breadcrumbs?.first?.message, "reading ~/.arcbox/config.toml")
        XCTAssertEqual(event.message?.formatted, "starting from ~/.arcbox")
    }
}
