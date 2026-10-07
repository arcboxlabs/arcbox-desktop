import SwiftUI

/// Says how many layers a Files tab merged, and warns when some of them
/// could not be read.
///
/// A layer the `~/ArcBox/docker` export cannot serve contributes nothing to the
/// merge, so the browser would otherwise present a partial filesystem as if
/// it were complete — files unique to that layer, and the deletions it
/// records, simply would not appear.
struct LayerMergeBadge: View {
    private let total: Int
    private let unavailable: Int
    private let describesAStack: Bool

    /// Describes a browsed stack, and renders nothing when there is no stack
    /// to describe — a single-layer subject, or one that could not be
    /// browsed at all.
    init(stack: LayerStack) {
        total = stack.reportedLayers
        unavailable = stack.missingLayers
        describesAStack = stack.describesAStack
    }

    private var isComplete: Bool { unavailable == 0 }

    @ViewBuilder
    var body: some View {
        if describesAStack {
            badge
        }
    }

    private var badge: some View {
        HStack(spacing: 4) {
            if !isComplete {
                Image(systemName: "exclamationmark.triangle.fill")
                    .font(.system(size: 10))
                    .accessibilityHidden(true)
            }

            Text(label)
                .font(.system(size: 11))
        }
        .foregroundStyle(isComplete ? AppColors.textMuted : AppColors.warning)
        .fixedSize()
        .accessibilityElement(children: .combine)
        .help(
            isComplete
                ? "Merged view of all \(total) filesystem layers."
                : "\(unavailable) of \(total) layers are unavailable through the ~/ArcBox/docker export; "
                    + "files that only exist in them are missing from this view."
        )
    }

    private var label: String { Self.label(total: total, unavailable: unavailable) }

    static func label(total: Int, unavailable: Int) -> String {
        unavailable == 0
            ? "merged from \(total) layers"
            : "merged from \(total - unavailable) of \(total) layers"
    }
}
