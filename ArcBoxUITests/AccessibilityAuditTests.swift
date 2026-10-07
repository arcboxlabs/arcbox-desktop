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
            try waitForListToSettle()
            try audit(section)
        }
    }

    func testMachinesAndSandboxes() throws {
        for section in ["Machines", "Sandboxes"] {
            select(sidebarRow: section)
            try waitForListToSettle()
            try audit(section)
        }
    }

    func testContainerDetailTabs() throws {
        select(sidebarRow: "Containers")
        try waitForListToSettle()
        let firstContainer = app.outlines["Containers"].cells.firstMatch
        guard firstContainer.waitForExistence(timeout: 5) else {
            throw XCTSkip("no containers on this Mac; detail tabs need a selected container")
        }
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
        let settings = app.windows["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5), "Settings window did not open")
        for pane in ["General", "System", "Storage"] {
            settings.outlines["Settings navigation"].staticTexts[pane].click()
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
        row.click()
    }

    /// The detail tab bar exposes itself as a segmented picker, so each tab is
    /// a radio button.
    private func select(detailTab title: String) {
        let tab = app.radioButtons[title].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 5), "detail tab \(title) missing")
        tab.click()
    }

    /// The lists show a loading placeholder until the daemon answers. Wait for
    /// that placeholder to go, so the audit sees rows or an empty state, not
    /// the spinner. Keyed on the placeholder's accessibility identifier rather
    /// than its wording: a resource named "Loading" must not hold the wait.
    /// A daemon that never comes up is this Mac's problem, not the UI's, so
    /// that skips the audit instead of failing it.
    private func waitForListToSettle() throws {
        let loading = app.windows.firstMatch.descendants(matching: .any)
            .matching(identifier: "placeholder.loading")
        let settled = expectation(for: NSPredicate(format: "count == 0"), evaluatedWith: loading)
        guard XCTWaiter().wait(for: [settled], timeout: 60) == .completed else {
            throw XCTSkip(
                "the daemon did not come up within 60s; a list still shows \(loading.firstMatch.label)")
        }
    }
}
