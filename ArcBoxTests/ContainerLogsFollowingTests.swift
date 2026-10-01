import AppKit
import DockerClient
import SwiftUI
import XCTest

@testable import ArcBox

/// Following in the logs tab: the last line stays visible as batches land, and
/// `isFollowing` — the toolbar's stream toggle — is the only thing that pauses
/// it. Scrolling up on its own changes nothing, as it never did; the next batch
/// returns to the end.
@MainActor
final class ContainerLogsFollowingTests: XCTestCase {
    func testHistoricalLogsOpenAtTheirLastLine() throws {
        let tab = try HostedLogsTab(seeded: 600)
        defer { tab.close() }

        XCTAssertGreaterThan(tab.scrollView.documentHeight, tab.scrollView.documentVisibleRect.height)
        XCTAssertTrue(tab.scrollView.isScrolledToBottom)
    }

    func testFollowingKeepsTheLastLineVisibleAfterEveryBatch() throws {
        var tab = try HostedLogsTab(seeded: 600)
        defer { tab.close() }
        let heightBefore = tab.scrollView.documentHeight

        for batch in 0..<20 {
            tab.appendBatch()
            XCTAssertTrue(tab.scrollView.isScrolledToBottom, "batch \(batch) left the end out of view")
        }
        XCTAssertGreaterThan(tab.scrollView.documentHeight, heightBefore)
    }

    func testScrollingUpDoesNotPauseFollowingAndTheNextBatchReturnsToTheEnd() throws {
        var tab = try HostedLogsTab(seeded: 600)
        defer { tab.close() }

        tab.scrollView.scroll(toY: 3000)
        tab.host.pump()
        XCTAssertEqual(tab.scrollView.documentVisibleRect.origin.y, 3000)
        XCTAssertTrue(tab.model.isFollowing, "only the toolbar toggle pauses following")

        tab.appendBatch()
        XCTAssertTrue(tab.scrollView.isScrolledToBottom)
    }

    func testPauseHoldsThePlaceAndFollowReturnsToTheEnd() throws {
        var tab = try HostedLogsTab(seeded: 600)
        defer { tab.close() }

        tab.model.toggleFollow()
        tab.host.pump()
        XCTAssertFalse(tab.model.isFollowing)
        tab.scrollView.scroll(toY: 3000)
        tab.host.pump()

        for _ in 0..<3 {
            tab.appendBatch()
            XCTAssertEqual(tab.scrollView.documentVisibleRect.origin.y, 3000, "paused, the view must not move")
        }

        tab.model.toggleFollow()
        tab.host.pump()
        XCTAssertTrue(tab.model.isFollowing)
        XCTAssertTrue(tab.scrollView.isScrolledToBottom, "Follow jumps to the end at once")

        tab.appendBatch()
        XCTAssertTrue(tab.scrollView.isScrolledToBottom)
    }

    func testANarrowedFilterKeepsFollowingTheMatches() throws {
        var tab = try HostedLogsTab(seeded: 600)
        defer { tab.close() }

        tab.model.streamFilter = .stderr
        tab.host.settle()
        XCTAssertLessThan(tab.scrollView.documentHeight, 600 * 10, "the stderr lines alone are listed")

        for _ in 0..<10 {
            tab.appendBatch()
            XCTAssertTrue(tab.scrollView.isScrolledToBottom)
        }
    }
}

/// A `ContainerLogsTab` hosted at a detail pane's size with `seeded` lines showing.
@MainActor
private struct HostedLogsTab {
    let model = ContainerLogsModel()
    let host: OffscreenHost
    let scrollView: NSScrollView
    private var next = 0

    init(seeded: Int) throws {
        host = OffscreenHost(
            ContainerLogsTab(container: ContainerLogsFixtures.container, model: model),
            contentSize: NSSize(width: 960, height: 640)
        )
        // `startStreaming` has run by now (no Docker client, so it only reset
        // the model); seed the buffer through the production path.
        model.errorMessage = nil
        model.append(ContainerLogsFixtures.lines(from: &next, count: seeded))
        host.settle()
        scrollView = try XCTUnwrap(host.scrollViews().first)
    }

    /// One streamed batch, laid out.
    mutating func appendBatch(of count: Int = 10) {
        model.append(ContainerLogsFixtures.lines(from: &next, count: count))
        host.pump()
    }

    func close() {
        host.close()
    }
}
