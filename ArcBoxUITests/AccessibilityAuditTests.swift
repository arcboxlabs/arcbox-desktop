import XCTest

/// Runs Xcode's accessibility audit over the main flows of the launched app.
///
/// Every element the audit reports is a VoiceOver-visible defect: a control
/// without a description, a hit region too small to reach, a parent/child
/// relationship the tree gets wrong. The audit only sees what is on screen,
/// so each test navigates to a surface first and then audits it.
///
/// Runs through `make audit-accessibility` against the signed development
/// build (`ArcBox Dev`): without its daemon the lists never leave the startup
/// placeholder, and the audit would only ever see that.
@MainActor
final class AccessibilityAuditTests: XCTestCase {
    private var app: XCUIApplication!

    override func setUp() async throws {
        try await super.setUp()
        // Keep going after the first issue: one run should list everything.
        continueAfterFailure = true
        app = XCUIApplication()
        // Skip onboarding: the argument domain overrides the stored value
        // without changing it. Same override `script/build_and_run.sh --verify`
        // uses.
        app.launchArguments = ["-hasCompletedOnboarding", "YES"]
        app.launch()
        waitForMainWindow()
    }

    override func tearDown() async throws {
        app.terminate()
        try await super.tearDown()
    }

    func testDockerLists() throws {
        for section in ["Containers", "Volumes", "Images", "Networks"] {
            select(sidebarRow: section)
            try waitForListToSettle(section)
            try audit(section)
        }
    }

    func testMachinesAndSandboxes() throws {
        for section in ["Machines", "Sandboxes"] {
            select(sidebarRow: section)
            try waitForListToSettle(section)
            try audit(section)
        }
    }

    func testContainerDetailTabs() throws {
        select(sidebarRow: "Containers")
        try waitForListToSettle("Containers")
        // Section and Compose group rows are not selectable containers.
        let firstContainer = app.outlines["Containers"].cells.matching(
            NSPredicate(format: "label MATCHES %@", ".+, .*, (Running|Stopped|Restarting|Paused|Dead)")
        ).firstMatch
        guard firstContainer.waitForExistence(timeout: 5) else {
            throw XCTSkip("no containers on this Mac; detail tabs need a selected container")
        }
        app.activate()
        firstContainer.click()
        for tab in ["Info", "Logs", "Terminal", "Files"] {
            select(detailTab: tab)
            try audit("Container \(tab) tab")
        }
    }

    func testSettingsPanes() throws {
        // Through the menu rather than ⌘,: under the test runner the main
        // window is not reliably key, so the shortcut can go nowhere.
        app.activate()
        app.menuBars.menuBarItems["ArcBox"].click()
        app.menuBars.menuItems["Settings…"].click()
        let navigation = app.outlines["Settings navigation"]
        XCTAssertTrue(navigation.waitForExistence(timeout: 5), "Settings navigation did not appear")
        for pane in ["General", "System", "Storage"] {
            navigation.staticTexts[pane].click()
            try audit("Settings › \(pane)")
        }
    }

    // MARK: - Audit

    private func audit(_ surface: String) throws {
        try app.performAccessibilityAudit(for: .all) { issue in
            XCTFail("\(surface): \(issue.compactDescription) — \(issue.detailedDescription)")
            return true
        }
    }

    // MARK: - Navigation

    private func waitForMainWindow() {
        let sidebar = app.outlines["Main navigation"]
        XCTAssertTrue(sidebar.waitForExistence(timeout: 15), "main window did not appear")
    }

    private func select(sidebarRow title: String) {
        let row = app.outlines["Main navigation"].staticTexts[title]
        XCTAssertTrue(row.waitForExistence(timeout: 5), "sidebar row \(title) missing")
        app.activate()
        row.click()
    }

    /// The detail tab bar exposes itself as a segmented picker, so each tab is
    /// a radio button.
    private func select(detailTab title: String) {
        let tab = app.radioButtons[title].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "detail tab \(title) missing")
        app.activate()
        tab.click()
    }

    /// Each list's subtitle starts with a count or size only after a successful
    /// load. Startup and error screens can have no loading placeholder.
    private func waitForListToSettle(_ section: String) throws {
        let loadedWindow = app.windows.matching(
            NSPredicate(format: "title MATCHES %@", "\(section) – [0-9].*")
        ).firstMatch
        guard loadedWindow.waitForExistence(timeout: 60) else {
            throw XCTSkip(
                "\(section) did not finish loading within 60s; window: \(app.windows.firstMatch.title)")
        }
    }
}
