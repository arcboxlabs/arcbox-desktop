import Foundation
import XCTest

/// The `log_privacy_public` custom SwiftLint rule decides which values may be
/// interpolated `.public` into the unified log. These tests pin its regex on
/// representative lines, so an edit that stops flagging identifiers or starts
/// flagging counts fails here rather than in review.
final class LogPrivacyLintRuleTests: XCTestCase {
    private var rule: NSRegularExpression!

    override func setUpWithError() throws {
        try super.setUpWithError()
        let configURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent(".swiftlint.yml")
        let config = try String(contentsOf: configURL, encoding: .utf8)
        let pattern = try XCTUnwrap(
            Self.regex(ofRule: "log_privacy_public", in: config),
            "log_privacy_public has no regex in .swiftlint.yml"
        )
        rule = try NSRegularExpression(pattern: pattern)
    }

    func testFlagsOpenEndedValues() {
        for line in [
            #"Log.container.info("Created container \(id, privacy: .public)")"#,
            #"Log.image.info("Pulled \(reference, privacy: .public)")"#,
            #"logger.error("Failed: \(error.localizedDescription, privacy: .public)")"#,
            #"ClientLog.daemon.error("Daemon binary not found at \(path, privacy: .public)")"#,
            #"Log.startup.info("Client for \(configuration.baseURL.absoluteString, privacy: .public)")"#,
            #"logger.warning("Failed to copy \(file, privacy: .private): \(error, privacy: .public)")"#,
            #"Log.volume.info("Created volume \(vol.Name, privacy: .public)")"#,
            #"Log.image.info("Loaded \(self.images.count + userID, privacy: .public)")"#,
            #"Log.container.info("Status \(container.status.description, privacy: .public)")"#,
        ] {
            XCTAssertTrue(matches(line), "should flag: \(line)")
        }
    }

    func testAllowsClosedSetValues() {
        for line in [
            #"Log.image.info("Loaded \(self.images.count, privacy: .public) images")"#,
            #"Log.container.error("Unexpected status \(statusCode, privacy: .public) creating container")"#,
            #"ClientLog.startup.info("\(step.label, privacy: .public) completed in \(elapsedMs, privacy: .public)ms")"#,
            #"ClientLog.daemon.info("SMAppService status: \(String(describing: status), privacy: .public)")"#,
            #"ClientLog.daemon.info("Helper installed (\(postInstallVersion ?? "unknown", privacy: .public))")"#,
            #"Log.sandbox.error("Sandbox \(operation, privacy: .public) failed: \(error, privacy: .private)")"#,
            #"Log.notifications.debug("\(notification.category.rawValue, privacy: .public) notifications are off")"#,
            #"Log.startup.info("PostHog initialized (opted \(optedOut ? "out" : "in", privacy: .public))")"#,
            #"Log.docker.debug("Debounced \(coalescedCount, privacy: .public) \(type, privacy: .public) events")"#,
            #"ClientLog.daemon.warning("Daemon still holds the lock after \(Self.shutdownTimeout, privacy: .public)")"#,
            #"Log.container.info("Created container \(id, privacy: .private(mask: .hash))")"#,
            #"Log.image.info("Pulled image \(reference, privacy: .private)")"#,
        ] {
            XCTAssertFalse(matches(line), "should allow: \(line)")
        }
    }

    private func matches(_ line: String) -> Bool {
        rule.firstMatch(in: line, range: NSRange(line.startIndex..., in: line)) != nil
    }

    /// The single-quoted `regex:` value of the named custom rule.
    private static func regex(ofRule rule: String, in config: String) -> String? {
        guard let ruleRange = config.range(of: "\n  \(rule):\n") else { return nil }
        let body = config[ruleRange.upperBound...]
        guard let regexRange = body.range(of: "regex: '") else { return nil }
        let start = body[regexRange.upperBound...]
        guard let end = start.range(of: "'\n") else { return nil }
        return String(start[..<end.lowerBound])
    }
}
