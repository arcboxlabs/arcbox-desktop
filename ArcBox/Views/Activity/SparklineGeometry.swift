import CoreGraphics
import SwiftUI

/// The shapes a sparkline draws for one frame of history: the plotted points,
/// the monotone line through them and the area under it, plus the
/// pointer-to-sample mapping scrubbing needs.
///
/// Pure geometry, kept apart from the view so the mapping and the paths are
/// unit-tested against exact coordinates. Samples are evenly spaced along x
/// (the history is one sample per tick, gap-free), oldest first, and y grows
/// downward as in a view.
nonisolated struct SparklineGeometry: Equatable {
    /// Where each sample lands, oldest first.
    let points: [CGPoint]
    let size: CGSize

    /// Places `values` in `size`, clamping each to `domain`.
    init(values: [Double], domain: ClosedRange<Double>, size: CGSize) {
        self.size = size
        let span = max(domain.upperBound - domain.lowerBound, .ulpOfOne)
        points = values.enumerated().map { offset, value in
            let clamped = min(max(value, domain.lowerBound), domain.upperBound)
            let unit = (clamped - domain.lowerBound) / span
            return CGPoint(
                x: Self.x(forSample: offset, count: values.count, width: size.width),
                y: size.height - CGFloat(unit) * size.height
            )
        }
    }

    /// Headroom above the observed peak so a flat-zero series still renders —
    /// the autoscale the byte-rate tiles use.
    static func autoDomain(for values: [Double]) -> ClosedRange<Double> {
        let peak = values.max() ?? 1
        return 0...max(peak * 1.2, 1)
    }

    /// The x of sample `offset` in a series of `count`: evenly spaced from the
    /// leading edge to the trailing one. A lone sample sits in the middle.
    static func x(forSample offset: Int, count: Int, width: CGFloat) -> CGFloat {
        guard count > 1 else { return width / 2 }
        return width * CGFloat(offset) / CGFloat(count - 1)
    }

    /// The sample nearest a pointer at `x`, or `nil` when there is nothing to
    /// pick. A pointer past either edge picks the sample at that edge, so a
    /// scrub that overshoots the strip still lands on the newest or oldest.
    static func sampleOffset(atX x: CGFloat, count: Int, width: CGFloat) -> Int? {
        guard count > 0, width > 0, x.isFinite else { return nil }
        guard count > 1 else { return 0 }
        let unit = min(max(x / width, 0), 1)
        return Int((unit * CGFloat(count - 1)).rounded())
    }

    /// A monotone cubic through the points. Empty below two points: a single
    /// sample is a marker, not a line.
    var line: Path {
        var path = Path()
        guard points.count > 1 else { return path }
        path.move(to: points[0])
        appendCurve(to: &path)
        return path
    }

    /// `line` closed down to the baseline, for the fill beneath it.
    var area: Path {
        var path = Path()
        guard let first = points.first, let last = points.last, points.count > 1 else { return path }
        path.move(to: CGPoint(x: first.x, y: size.height))
        path.addLine(to: first)
        appendCurve(to: &path)
        path.addLine(to: CGPoint(x: last.x, y: size.height))
        path.closeSubpath()
        return path
    }

    /// Fritsch–Carlson monotone interpolation, as `d3.curveMonotoneX` and
    /// Swift Charts' `.monotone` draw it: the curve never overshoots a sample,
    /// so a spike reads as a spike and a plateau stays flat.
    private func appendCurve(to path: inout Path) {
        let slopes = tangents
        for index in 0..<(points.count - 1) {
            let from = points[index]
            let to = points[index + 1]
            let dx = (to.x - from.x) / 3
            path.addCurve(
                to: to,
                control1: CGPoint(x: from.x + dx, y: from.y + dx * slopes[index]),
                control2: CGPoint(x: to.x - dx, y: to.y - dx * slopes[index + 1])
            )
        }
    }

    /// One tangent per point. Interior tangents are the sign-preserving
    /// weighted mean of the neighbouring secants, zero at a local extremum;
    /// the ends extrapolate from the first and last segments.
    private var tangents: [CGFloat] {
        let count = points.count
        guard count > 1 else { return Array(repeating: 0, count: count) }
        var slopes = [CGFloat](repeating: 0, count: count)
        for index in 1..<(count - 1) {
            slopes[index] = Self.interiorSlope(points[index - 1], points[index], points[index + 1])
        }
        slopes[0] = Self.endSlope(points[0], points[1], neighbour: slopes[1])
        slopes[count - 1] = Self.endSlope(points[count - 2], points[count - 1], neighbour: slopes[count - 2])
        return slopes
    }

    private static func interiorSlope(_ p0: CGPoint, _ p1: CGPoint, _ p2: CGPoint) -> CGFloat {
        let h0 = p1.x - p0.x
        let h1 = p2.x - p1.x
        let s0 = (p1.y - p0.y) / (h0 == 0 ? h1 : h0)
        let s1 = (p2.y - p1.y) / (h1 == 0 ? h0 : h1)
        let weighted = (s0 * h1 + s1 * h0) / (h0 + h1)
        let sign = (s0 < 0 ? -1 : s0 > 0 ? 1 : 0) + (s1 < 0 ? -1 : s1 > 0 ? 1 : 0)
        return CGFloat(sign) * min(abs(s0), abs(s1), abs(weighted) / 2)
    }

    /// The one-sided tangent that keeps the end segment's curvature continuous
    /// with the interior; with two points it is the secant itself.
    private static func endSlope(_ p0: CGPoint, _ p1: CGPoint, neighbour: CGFloat) -> CGFloat {
        let h = p1.x - p0.x
        guard h != 0 else { return neighbour }
        return (3 * (p1.y - p0.y) / h - neighbour) / 2
    }
}
