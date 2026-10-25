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

    @MainActor func testRoutesEverySectionWithoutID() {
        let (router, appVM) = makeRouter()

        for item in NavItem.allCases {
            router.handle(URL(string: "arcbox://\(item.rawValue)")!)

            XCTAssertEqual(appVM.currentNav, item)
            XCTAssertNil(appVM.pendingResourceDeepLink)
            XCTAssertNil(appVM.deepLinkError)
        }
    }

    @MainActor func testResolvesValidAndReportsMissingIDsForEveryResourceSection() {
        let (router, appVM) = makeRouter()
        let resourceSections = NavItem.allCases.filter { $0 != .activity && $0 != .runner }

        for item in resourceSections {
            let validID = "valid-\(item.rawValue)"
            router.handle(URL(string: "arcbox://\(item.rawValue)/\(validID)")!)

            let resolved = appVM.resolveResourceDeepLink(
                availableIDs: [validID],
                isLoaded: true
            )
            XCTAssertEqual(resolved?.section, item)
            XCTAssertEqual(resolved?.id, validID)
            XCTAssertNil(appVM.deepLinkError)

            let missingID = "missing-\(item.rawValue)"
            router.handle(URL(string: "arcbox://\(item.rawValue)/\(missingID)")!)

            XCTAssertNil(
                appVM.resolveResourceDeepLink(availableIDs: [validID], isLoaded: true)
            )
            XCTAssertEqual(
                appVM.deepLinkError,
                "Resource “\(missingID)” wasn’t found in \(item.label)."
            )
        }
    }

    @MainActor func testWaitsForFreshResourceListBeforeResolvingID() {
        let (router, appVM) = makeRouter()
        router.handle(URL(string: "arcbox://machines/machine-id")!)

        XCTAssertNil(
            appVM.resolveResourceDeepLink(
                availableIDs: ["machine-id"],
                isLoaded: false
            )
        )
        XCTAssertEqual(appVM.pendingResourceDeepLink?.section, .machines)
        XCTAssertEqual(appVM.pendingResourceDeepLink?.id, "machine-id")
        XCTAssertNil(appVM.deepLinkError)
    }

    @MainActor func testRejectsSectionsWithoutResourceSelectionVisibly() {
        let (router, appVM) = makeRouter()

        for item in [NavItem.activity, .runner] {
            router.handle(URL(string: "arcbox://\(item.rawValue)/resource-id")!)

            XCTAssertEqual(appVM.currentNav, item)
            XCTAssertNil(appVM.pendingResourceDeepLink)
            XCTAssertEqual(
                appVM.deepLinkError,
                "\(item.label) links don’t support resource IDs."
            )
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

    @MainActor func testRejectsUnavailableTemplatesSection() {
        XCTAssertNil(parse("arcbox://templates"))
    }

    @MainActor private func makeRouter() -> (DeepLinkRouter, AppViewModel) {
        let router = DeepLinkRouter()
        let appVM = AppViewModel()
        router.configure(
            .init(
                appVM: appVM,
                openMainWindow: {},
                openSettingsWindow: {}
            )
        )
        return (router, appVM)
    }

    // MARK: - URL round-trip

    /// Notifications carry their destination as a URL string, so every link
    /// must survive the trip back through the parser.
    @MainActor func testURLRoundTrips() {
        let links: [DeepLink] = [
            .main,
            .settings,
            .section(.sandboxes, id: nil),
            .section(.containers, id: "abc123"),
        ]
        for link in links {
            XCTAssertEqual(DeepLink(link.url), link, "\(link.url) did not round-trip")
        }
    }

    @MainActor func testURLEscapesIDs() {
        let link = DeepLink.section(.containers, id: "a b/c")
        XCTAssertEqual(DeepLink(link.url), .section(.containers, id: "a b"))
    }
}
