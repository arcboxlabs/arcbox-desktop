import Foundation

// MARK: - Changelog Data Model

/// A single section within a release (e.g. "Features", "Bug Fixes").
struct ChangelogSection: Identifiable, Sendable {
    var id: String { title }
    let title: String
    let items: [String]
}

/// A parsed release entry from CHANGELOG.md.
struct ChangelogRelease: Identifiable, Sendable {
    var id: String { version }
    let version: String
    let date: String
    let sections: [ChangelogSection]
}

// MARK: - Parser

/// Parses conventional-commits CHANGELOG.md into structured release entries.
enum ChangelogParser {
    /// Load and parse CHANGELOG.md from the app bundle.
    /// Returns the most recent `limit` releases.
    static func loadFromBundle(limit: Int = 5) -> [ChangelogRelease] {
        guard let url = Bundle.main.url(forResource: "CHANGELOG", withExtension: "md"),
            let content = try? String(contentsOf: url, encoding: .utf8)
        else {
            return []
        }
        return parse(content, limit: limit)
    }

    /// Parse raw CHANGELOG.md text into structured releases.
    /// - Parameters:
    ///   - text: Raw markdown content of CHANGELOG.md
    ///   - limit: Maximum number of releases to return
    /// - Returns: Array of parsed releases, newest first
    static func parse(_ text: String, limit: Int = 5) -> [ChangelogRelease] {
        let versionPattern = /^## \[(.+?)\](?:\(.+?\))?\s+\((\d{4}-\d{2}-\d{2})\)/
        let sectionPattern = /^### (.+)/

        var releases: [ChangelogRelease] = []
        var currentVersion: String?
        var currentDate: String?
        var currentSections: [ChangelogSection] = []
        var currentSectionTitle: String?
        var currentItems: [String] = []

        func flushSection() {
            if let title = currentSectionTitle, !currentItems.isEmpty {
                currentSections.append(ChangelogSection(title: title, items: currentItems))
            }
            currentSectionTitle = nil
            currentItems = []
        }

        func flushRelease() {
            flushSection()
            if let version = currentVersion, let date = currentDate {
                releases.append(
                    ChangelogRelease(
                        version: version, date: date, sections: currentSections
                    ))
            }
            currentVersion = nil
            currentDate = nil
            currentSections = []
        }

        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)

            if let match = trimmed.firstMatch(of: versionPattern) {
                flushRelease()
                if releases.count >= limit { break }
                currentVersion = String(match.1)
                currentDate = String(match.2)
            } else if let match = trimmed.firstMatch(of: sectionPattern) {
                flushSection()
                currentSectionTitle = String(match.1)
            } else if trimmed.hasPrefix("* ") {
                currentItems.append(cleanItem(String(trimmed.dropFirst(2))))
            }
        }

        // Flush the last in-progress release.
        if releases.count < limit {
            flushRelease()
        }

        return releases
    }

    // MARK: - Private

    /// Strip markdown link syntax from a changelog item for display.
    /// - Removes commit hash links: ([abc1234](url))
    /// - Converts issue links: ([#123](url)) → #123
    /// - Removes bold scope markers: **scope:** → scope:
    private static func cleanItem(_ text: String) -> String {
        var result = text
        // Remove commit hash links: ([a771d71](https://...))
        result = result.replacingOccurrences(
            of: #"\s*\(\[[a-f0-9]+\]\([^)]+\)\)"#,
            with: "",
            options: .regularExpression
        )
        // Convert issue links to plain text: ([#202](url)) → #202
        result = result.replacingOccurrences(
            of: #"\(\[(#\d+)\]\([^)]+\)\)"#,
            with: "$1",
            options: .regularExpression
        )
        // Remove bold scope prefix: **settings:** → settings:
        result = result.replacingOccurrences(
            of: #"\*\*(.+?):\*\*"#,
            with: "$1:",
            options: .regularExpression
        )
        return result.trimmingCharacters(in: .whitespaces)
    }
}
