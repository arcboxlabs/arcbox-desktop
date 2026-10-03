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
    let highlights: String?
    let sections: [ChangelogSection]
}

// MARK: - Parser

/// Parses conventional-commits CHANGELOG.md into structured release entries.
enum ChangelogParser {
    /// Load and parse CHANGELOG.md from the app bundle.
    /// Returns the most recent `limit` releases.
    nonisolated static func loadFromBundle(limit: Int = 5) -> [ChangelogRelease] {
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
    nonisolated static func parse(_ text: String, limit: Int = 5) -> [ChangelogRelease] {
        let versionPattern = /^## \[(.+?)\](?:\(.+?\))?\s+\((\d{4}-\d{2}-\d{2})\)/
        let sectionPattern = /^### (.+)/
        let userFacingSectionTitles = Set(["Features", "Bug Fixes", "Performance", "Security"])

        var releases: [ChangelogRelease] = []
        var currentVersion: String?
        var currentDate: String?
        var currentHighlights: String?
        var currentSections: [ChangelogSection] = []
        var currentSectionTitle: String?
        var currentSectionLines: [String] = []

        func flushSection() {
            if let title = currentSectionTitle {
                if title == "Highlights" {
                    currentHighlights = cleanHighlights(currentSectionLines)
                } else if userFacingSectionTitles.contains(title) {
                    let items = currentSectionLines.compactMap { line -> String? in
                        let trimmed = line.trimmingCharacters(in: .whitespaces)
                        guard trimmed.hasPrefix("* ") else { return nil }
                        let item = cleanItem(String(trimmed.dropFirst(2)))
                        return item.isEmpty ? nil : item
                    }
                    if !items.isEmpty {
                        currentSections.append(ChangelogSection(title: title, items: items))
                    }
                }
            }
            currentSectionTitle = nil
            currentSectionLines = []
        }

        func flushRelease() {
            flushSection()
            if let version = currentVersion, let date = currentDate,
                currentHighlights != nil || !currentSections.isEmpty
            {
                releases.append(
                    ChangelogRelease(
                        version: version,
                        date: date,
                        highlights: currentHighlights,
                        sections: currentSections
                    ))
            }
            currentVersion = nil
            currentDate = nil
            currentHighlights = nil
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
            } else if currentSectionTitle != nil {
                currentSectionLines.append(line)
            }
        }

        // Flush the last in-progress release.
        if releases.count < limit {
            flushRelease()
        }

        return releases
    }

    // MARK: - Private

    /// Strip developer-facing markdown plumbing from a legacy changelog item.
    /// - Removes commit hash links: ([abc1234](url))
    /// - Removes issue/PR links: ([#123](url))
    /// - Removes conventional-commit scopes: **scope:**
    nonisolated private static func cleanItem(_ text: String) -> String {
        var result = text
        // Remove commit hash links: ([a771d71](https://...))
        result = result.replacingOccurrences(
            of: #"\s*\(\[[a-f0-9]+\]\([^)]+\)\)"#,
            with: "",
            options: .regularExpression
        )
        // Remove issue/PR links: ([#202](url))
        result = result.replacingOccurrences(
            of: #"\s*\(\[#\d+\]\([^)]+\)\)"#,
            with: "",
            options: .regularExpression
        )
        // Remove a conventional-commit scope prefix: **settings:**
        result = result.replacingOccurrences(
            of: #"^\*\*[^*]+:\*\*\s*"#,
            with: "",
            options: .regularExpression
        )
        return result.trimmingCharacters(in: .whitespaces)
    }

    /// Convert soft-wrapped Markdown under `### Highlights` into display prose.
    nonisolated private static func cleanHighlights(_ lines: [String]) -> String? {
        var paragraphs: [String] = []
        var currentLines: [String] = []

        func flushParagraph() {
            if !currentLines.isEmpty {
                paragraphs.append(currentLines.joined(separator: " "))
                currentLines = []
            }
        }

        for rawLine in lines {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            if line.hasPrefix(">") {
                line = String(line.dropFirst()).trimmingCharacters(in: .whitespaces)
            }
            if line == "[!IMPORTANT]" {
                continue
            }
            guard !line.isEmpty else {
                flushParagraph()
                continue
            }

            var cleaned = line.replacingOccurrences(
                of: #"\[([^]]+)\]\([^)]+\)"#,
                with: "$1",
                options: .regularExpression
            )
            for marker in ["**", "__", "`"] {
                cleaned = cleaned.replacingOccurrences(of: marker, with: "")
            }
            currentLines.append(cleaned)
        }
        flushParagraph()

        let highlights = paragraphs.joined(separator: "\n\n")
        return highlights.isEmpty ? nil : highlights
    }
}
