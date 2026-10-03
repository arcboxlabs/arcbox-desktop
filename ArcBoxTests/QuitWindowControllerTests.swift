import AppKit
import XCTest

@testable import ArcBox

@MainActor
final class QuitWindowControllerTests: XCTestCase {
    func testQuitCardIsTheOnlyNonInteractiveWindowSurface() throws {
        let controller = QuitWindowController()
        let window = try XCTUnwrap(controller.window)

        XCTAssertEqual(window.frame.size, QuitWindowController.cardSize)
        XCTAssertEqual(window.styleMask, .borderless)
        XCTAssertEqual(window.level, .modalPanel)
        XCTAssertFalse(window.canBecomeKey)
        XCTAssertFalse(window.canBecomeMain)
        XCTAssertFalse(window.isMovable)
        XCTAssertTrue(window.ignoresMouseEvents)
        XCTAssertTrue(window.isExcludedFromWindowsMenu)
        XCTAssertNil(window.standardWindowButton(.closeButton))
        XCTAssertNil(window.standardWindowButton(.miniaturizeButton))
        XCTAssertNil(window.standardWindowButton(.zoomButton))
    }
}
