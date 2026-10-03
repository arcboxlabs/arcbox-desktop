import XCTest

@testable import ArcBox

final class AppDelegateTestHostTests: XCTestCase {
    /// The detection is only worth anything in the process it protects: this suite runs
    /// inside the host the app delegate must recognise, so it pins that it does.
    func testTheTestHostIsRecognised() {
        XCTAssertTrue(AppDelegate.isTestHost)
    }
}
