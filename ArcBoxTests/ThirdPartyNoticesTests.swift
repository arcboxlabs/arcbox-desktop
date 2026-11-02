import Foundation
import XCTest

@testable import ArcBox

/// The app's notices window decodes `ThirdPartyNotices/components.json` from
/// the bundle. A key renamed on one side, or a license path that does not
/// exist, would ship an app whose notices cannot be read.
final class ThirdPartyNoticesTests: XCTestCase {
    func testBundledNoticesDecodeAndEveryLicenseFileExists() throws {
        let directory = try XCTUnwrap(ThirdPartyNotices.bundled)
        let notices = try ThirdPartyNotices.load(from: directory)

        XCTAssertFalse(notices.groups.isEmpty)
        for group in notices.groups {
            XCTAssertFalse(group.components.isEmpty, "group \(group.id) lists no components")
            for component in group.components {
                for path in component.licenseFiles {
                    let url = directory.appendingPathComponent(path)
                    let size = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize
                    XCTAssertGreaterThan(size ?? 0, 0, "\(component.name) references missing \(path)")
                }
            }
        }
    }
}
