import XCTest

@testable import ArcBox

final class ChangelogParserTests: XCTestCase {

    // MARK: - Version Header Parsing

    func testParsesVersionHeaderWithDate() {
        let input = """
            ## [1.2.0](https://example.com) (2026-03-15)

            ### Features

            * first feature
            """
        let releases = ChangelogParser.parse(input)
        XCTAssertEqual(releases.count, 1)
        XCTAssertEqual(releases.first?.version, "1.2.0")
        XCTAssertEqual(releases.first?.date, "2026-03-15")
    }

    func testParsesVersionHeaderWithoutLink() {
        let input = """
            ## [0.9.0] (2025-12-01)

            ### Bug Fixes

            * a fix
            """
        let releases = ChangelogParser.parse(input)
        XCTAssertEqual(releases.count, 1)
        XCTAssertEqual(releases.first?.version, "0.9.0")
    }

    // MARK: - Section Parsing

    func testParsesMultipleSections() {
        let input = """
            ## [2.0.0](https://example.com) (2026-04-01)

            ### Features

            * new dashboard
            * dark mode

            ### Bug Fixes

            * crash on launch
            """
        let releases = ChangelogParser.parse(input)
        XCTAssertEqual(releases.count, 1)

        let sections = releases.first!.sections
        XCTAssertEqual(sections.count, 2)
        XCTAssertEqual(sections[0].title, "Features")
        XCTAssertEqual(sections[0].items.count, 2)
        XCTAssertEqual(sections[1].title, "Bug Fixes")
        XCTAssertEqual(sections[1].items.count, 1)
    }

    // MARK: - Bullet Items

    func testParsesBulletItems() {
        let input = """
            ## [1.0.0](https://example.com) (2026-01-01)

            ### Features

            * alpha feature
            * beta feature
            * gamma feature
            """
        let releases = ChangelogParser.parse(input)
        let items = releases.first!.sections.first!.items
        XCTAssertEqual(items, ["alpha feature", "beta feature", "gamma feature"])
    }

    func testIgnoresNonBulletLines() {
        let input = """
            ## [1.0.0](https://example.com) (2026-01-01)

            ### Features

            Some description paragraph that should be ignored.

            * actual item
            """
        let releases = ChangelogParser.parse(input)
        let items = releases.first!.sections.first!.items
        XCTAssertEqual(items, ["actual item"])
    }

    // MARK: - cleanItem: Commit Hash Removal

    func testRemovesCommitHashLinks() {
        let input = """
            ## [1.0.0](https://example.com) (2026-01-01)

            ### Bug Fixes

            * fix startup crash ([a771d71](https://github.com/org/repo/commit/a771d71))
            """
        let releases = ChangelogParser.parse(input)
        let item = releases.first!.sections.first!.items.first!
        XCTAssertEqual(item, "fix startup crash")
    }

    // MARK: - cleanItem: Issue Link Conversion

    func testConvertsIssueLinksToPlainText() {
        let input = """
            ## [1.0.0](https://example.com) (2026-01-01)

            ### Bug Fixes

            * fix timeout ([#202](https://github.com/org/repo/issues/202))
            """
        let releases = ChangelogParser.parse(input)
        let item = releases.first!.sections.first!.items.first!
        XCTAssertEqual(item, "fix timeout #202")
    }

    // MARK: - cleanItem: Bold Scope Removal

    func testRemovesBoldScopeMarkers() {
        let input = """
            ## [1.0.0](https://example.com) (2026-01-01)

            ### Features

            * **settings:** wire up functional settings
            """
        let releases = ChangelogParser.parse(input)
        let item = releases.first!.sections.first!.items.first!
        XCTAssertEqual(item, "settings: wire up functional settings")
    }

    // MARK: - cleanItem: Combined Cleanup

    func testCombinedCleanup() {
        let input = """
            ## [1.0.0](https://example.com) (2026-01-01)

            ### Bug Fixes

            * **completions:** install all bundled completions ([#205](https://github.com/org/repo/issues/205)) ([01f6c7a](https://github.com/org/repo/commit/01f6c7a))
            """
        let releases = ChangelogParser.parse(input)
        let item = releases.first!.sections.first!.items.first!
        XCTAssertEqual(item, "completions: install all bundled completions #205")
    }

    // MARK: - Limit Parameter

    func testLimitParameter() {
        let input = """
            ## [3.0.0](https://example.com) (2026-03-01)

            ### Features

            * third release

            ## [2.0.0](https://example.com) (2026-02-01)

            ### Features

            * second release

            ## [1.0.0](https://example.com) (2026-01-01)

            ### Features

            * first release
            """
        let two = ChangelogParser.parse(input, limit: 2)
        XCTAssertEqual(two.count, 2)
        XCTAssertEqual(two[0].version, "3.0.0")
        XCTAssertEqual(two[1].version, "2.0.0")

        let one = ChangelogParser.parse(input, limit: 1)
        XCTAssertEqual(one.count, 1)
        XCTAssertEqual(one.first?.version, "3.0.0")
    }

    // MARK: - Empty / Malformed Input

    func testEmptyInputReturnsEmpty() {
        let releases = ChangelogParser.parse("")
        XCTAssertTrue(releases.isEmpty)
    }

    func testMalformedHeadersAreSkipped() {
        let input = """
            # Not a version header

            ## Missing date bracket [1.0.0]

            Some random text
            """
        let releases = ChangelogParser.parse(input)
        XCTAssertTrue(releases.isEmpty)
    }

    func testReleaseWithNoSectionsIsIncluded() {
        // A version header with no ### sections and no items still produces a release
        // (with empty sections array).
        let input = """
            ## [1.0.0](https://example.com) (2026-01-01)

            """
        let releases = ChangelogParser.parse(input)
        XCTAssertEqual(releases.count, 1)
        XCTAssertTrue(releases.first!.sections.isEmpty)
    }

    func testReleaseWithEmptySectionsAreExcluded() {
        // A section header with no bullet items is not included in sections.
        let input = """
            ## [1.0.0](https://example.com) (2026-01-01)

            ### Features

            ### Bug Fixes

            * actual fix
            """
        let releases = ChangelogParser.parse(input)
        let sections = releases.first!.sections
        // "Features" section has no items, so it should be excluded.
        XCTAssertEqual(sections.count, 1)
        XCTAssertEqual(sections.first?.title, "Bug Fixes")
    }
}
