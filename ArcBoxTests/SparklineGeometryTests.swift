import SwiftUI
import XCTest

@testable import ArcBox

/// The sparkline's layout rules: where samples land, how a pointer reads back
/// as a sample, and the shape of the curve through them.
final class SparklineGeometryTests: XCTestCase {

    // MARK: - Pointer → sample

    func testPointerPicksTheNearestSample() {
        XCTAssertEqual(SparklineGeometry.sampleOffset(atX: 0, count: 60, width: 300), 0)
        XCTAssertEqual(SparklineGeometry.sampleOffset(atX: 300, count: 60, width: 300), 59)
        XCTAssertEqual(
            SparklineGeometry.sampleOffset(atX: 100, count: 60, width: 300), 20,
            "100/300 of 59 steps is 19.67, which rounds to sample 20")
        XCTAssertEqual(
            SparklineGeometry.sampleOffset(atX: 2, count: 60, width: 300), 0,
            "a pointer just inside the leading edge is still on the oldest sample")
    }

    /// The pointer and the plot share one coordinate space (the figure's), so
    /// the sample under the pointer is the one drawn there: a quarter of the
    /// way across 60 samples is sample 15, and the ends land on the first and
    /// last samples' centres exactly.
    func testPointerLandsOnTheSampleDrawnThere() {
        XCTAssertEqual(SparklineGeometry.sampleOffset(atX: 37.5, count: 60, width: 150), 15)
        XCTAssertEqual(SparklineGeometry.sampleOffset(atX: 0, count: 60, width: 150), 0)
        XCTAssertEqual(SparklineGeometry.sampleOffset(atX: 150, count: 60, width: 150), 59)
        for offset in [0, 1, 29, 30, 58, 59] {
            let x = SparklineGeometry.x(forSample: offset, count: 60, width: 150)
            XCTAssertEqual(
                SparklineGeometry.sampleOffset(atX: x, count: 60, width: 150), offset,
                "the pointer on sample \(offset)'s own x must pick it")
        }
    }

    func testPointerPastAnEdgeClampsToThatEdge() {
        XCTAssertEqual(SparklineGeometry.sampleOffset(atX: -25, count: 60, width: 300), 0)
        XCTAssertEqual(SparklineGeometry.sampleOffset(atX: 1_000, count: 60, width: 300), 59)
    }

    func testPointerOverASingleSamplePicksIt() {
        XCTAssertEqual(SparklineGeometry.sampleOffset(atX: 0, count: 1, width: 300), 0)
        XCTAssertEqual(SparklineGeometry.sampleOffset(atX: 299, count: 1, width: 300), 0)
    }

    func testPointerOverNothingPicksNothing() {
        XCTAssertNil(SparklineGeometry.sampleOffset(atX: 10, count: 0, width: 300))
        XCTAssertNil(SparklineGeometry.sampleOffset(atX: 10, count: 60, width: 0), "no width, no mapping")
        XCTAssertNil(SparklineGeometry.sampleOffset(atX: .nan, count: 60, width: 300))
    }

    // MARK: - Sample → point

    func testSamplesSpreadEvenlyWithTheNewestAtTheTrailingEdge() {
        let xs = (0..<4).map { SparklineGeometry.x(forSample: $0, count: 4, width: 90) }
        XCTAssertEqual(xs, [0, 30, 60, 90])
        XCTAssertEqual(SparklineGeometry.x(forSample: 0, count: 1, width: 90), 45, "a lone sample is centred")
    }

    func testValuesMapIntoTheDomainAndClampOutsideIt() {
        let geometry = SparklineGeometry(
            values: [-5, 0, 50, 100, 150],
            domain: 0...100,
            size: CGSize(width: 100, height: 30)
        )
        XCTAssertEqual(geometry.points.map(\.y), [30, 30, 15, 0, 0])
    }

    func testAutoDomainKeepsHeadroomAndAFloor() {
        XCTAssertEqual(
            SparklineGeometry.autoDomain(for: []).upperBound, 1.2, accuracy: 1e-9,
            "no samples yet reads as an empty unit range, the same as the chart it replaces")
        XCTAssertEqual(SparklineGeometry.autoDomain(for: [0, 0, 0]), 0...1, "a flat-zero series still has a range")
        let headroom = SparklineGeometry.autoDomain(for: [10, 40])
        XCTAssertEqual(headroom.lowerBound, 0)
        XCTAssertEqual(headroom.upperBound, 48, accuracy: 1e-9)
    }

    // MARK: - Paths

    func testLineAndAreaNeedTwoSamples() {
        let size = CGSize(width: 100, height: 30)
        XCTAssertTrue(SparklineGeometry(values: [], domain: 0...1, size: size).line.isEmpty)
        XCTAssertTrue(SparklineGeometry(values: [], domain: 0...1, size: size).area.isEmpty)
        XCTAssertTrue(SparklineGeometry(values: [0.5], domain: 0...1, size: size).line.isEmpty)
        XCTAssertTrue(SparklineGeometry(values: [0.5], domain: 0...1, size: size).area.isEmpty)
        XCTAssertFalse(SparklineGeometry(values: [0.5, 0.6], domain: 0...1, size: size).line.isEmpty)
    }

    func testAreaRestsOnTheBaselineAcrossTheFullWidth() {
        let geometry = SparklineGeometry(
            values: [20, 80, 40, 60],
            domain: 0...100,
            size: CGSize(width: 120, height: 30)
        )
        let bounds = geometry.area.boundingRect
        XCTAssertEqual(bounds.minX, 0)
        XCTAssertEqual(bounds.maxX, 120)
        XCTAssertEqual(bounds.maxY, 30, "the fill closes down to the bottom of the figure")
    }

    /// Monotone interpolation: the curve between two equal samples stays flat,
    /// and the tangent at an extremum is zero, so a plateau reads as a plateau
    /// and a spike does not ring.
    func testCurveStaysFlatAcrossAPlateauAndLevelAtAPeak() {
        let geometry = SparklineGeometry(
            values: [0, 50, 50, 50, 100, 0],
            domain: 0...100,
            size: CGSize(width: 100, height: 100)
        )
        let curves = geometry.line.curves
        XCTAssertEqual(curves.count, 5)

        let plateauY = geometry.points[1].y
        for segment in curves[1...2] {
            XCTAssertEqual(segment.control1.y, plateauY, accuracy: 1e-9)
            XCTAssertEqual(segment.control2.y, plateauY, accuracy: 1e-9)
        }

        let peakY = geometry.points[4].y
        XCTAssertEqual(curves[3].control2.y, peakY, accuracy: 1e-9, "the tangent into the peak is level")
        XCTAssertEqual(curves[4].control1.y, peakY, accuracy: 1e-9, "and so is the tangent out of it")
    }

    func testCurveControlPointsNeverOvershootTheirSegment() {
        let geometry = SparklineGeometry(
            values: [10, 90, 20, 95, 5, 60, 30],
            domain: 0...100,
            size: CGSize(width: 300, height: 40)
        )
        for (offset, segment) in geometry.line.curves.enumerated() {
            let from = geometry.points[offset]
            let to = geometry.points[offset + 1]
            let range = min(from.y, to.y)...max(from.y, to.y)
            XCTAssertTrue(range.contains(segment.control1.y), "segment \(offset) overshoots at its start")
            XCTAssertTrue(range.contains(segment.control2.y), "segment \(offset) overshoots at its end")
        }
    }
}

extension Path {
    fileprivate struct Curve {
        let to: CGPoint
        let control1: CGPoint
        let control2: CGPoint
    }

    fileprivate var curves: [Curve] {
        var curves: [Curve] = []
        forEach { element in
            if case .curve(let to, let control1, let control2) = element {
                curves.append(Curve(to: to, control1: control1, control2: control2))
            }
        }
        return curves
    }
}
