import XCTest

@testable import ArcBox

final class DeepLinkTests: XCTestCase {

    @MainActor private func parse(_ string: String) -> DeepLink? {
        DeepLink(URL(string: string)!)
    }

    // MARK: - Window links

    @MainActor func testParsesMain() {
        XCTAssertEqual(parse("arcbox://main"), .main)
    }

    @MainActor func testParsesEmptyHostAsMain() {
        XCTAssertEqual(parse("arcbox://"), .main)
    }

    @MainActor func testParsesSettings() {
        XCTAssertEqual(parse("arcbox://settings"), .settings)
    }

    // MARK: - Section links

    @MainActor func testParsesSectionWithoutID() {
        XCTAssertEqual(parse("arcbox://containers"), .section(.containers, id: nil))
    }

    @MainActor func testParsesSectionWithTrailingSlashWithoutID() {
        XCTAssertEqual(parse("arcbox://images/"), .section(.images, id: nil))
    }

    @MainActor func testParsesSectionWithID() {
        XCTAssertEqual(parse("arcbox://containers/abc123"), .section(.containers, id: "abc123"))
    }

    @MainActor func testParsesEverySection() {
        for item in NavItem.allCases {
            XCTAssertEqual(parse("arcbox://\(item.rawValue)"), .section(item, id: nil))
        }
    }

    @MainActor func testDecodesPercentEncodedID() {
        XCTAssertEqual(parse("arcbox://volumes/my%20volume"), .section(.volumes, id: "my volume"))
    }

    @MainActor func testUsesFirstPathComponentAsID() {
        XCTAssertEqual(parse("arcbox://containers/abc/extra"), .section(.containers, id: "abc"))
    }

    @MainActor func testHostIsCaseInsensitive() {
        XCTAssertEqual(parse("arcbox://Containers"), .section(.containers, id: nil))
        XCTAssertEqual(parse("ARCBOX://settings"), .settings)
    }

    // MARK: - Rejection

    @MainActor func testRejectsOtherSchemes() {
        XCTAssertNil(parse("https://containers/abc"))
    }

    @MainActor func testRejectsUnknownHost() {
        XCTAssertNil(parse("arcbox://bogus"))
    }
}
