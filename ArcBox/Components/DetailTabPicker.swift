import SwiftUI

/// The tab set of a detail view.
///
/// Every conforming enum already satisfies each requirement; the protocol
/// exists so `DetailTabPicker` can name them in one place.
///
/// Conformers write `@MainActor DetailTab`. The target builds with
/// `SWIFT_DEFAULT_ACTOR_ISOLATION: MainActor`, so each enum's hand-written
/// `Identifiable` conformance is main-actor isolated, and a conformance that
/// depends on it has to say so.
protocol DetailTab: CaseIterable, Identifiable, Hashable, RawRepresentable
where RawValue == String, AllCases: RandomAccessCollection {}

/// The segmented tab bar in a detail view's toolbar.
///
/// The width follows the tab count with a three-segment floor, so single-tab
/// detail views keep the same toolbar presence instead of collapsing to a chip.
struct DetailTabPicker<Tab: DetailTab>: ToolbarContent {
    @Binding var selection: Tab

    var body: some ToolbarContent {
        if #available(macOS 26.0, *) {
            ToolbarItem(placement: .principal) {
                LiquidGlassDetailTabPicker(selection: $selection)
            }
            .sharedBackgroundVisibility(.visible)
        } else {
            ToolbarItem(placement: .principal) {
                Picker("Tab", selection: $selection) {
                    ForEach(Tab.allCases) { tab in
                        Text(tab.rawValue).tag(tab)
                    }
                }
                .pickerStyle(.segmented)
                .frame(
                    minWidth: DetailTabLayout.minimumWidth(for: Tab.allCases.count),
                    idealWidth: DetailTabLayout.idealWidth(for: Tab.allCases.count),
                    maxWidth: DetailTabLayout.idealWidth(for: Tab.allCases.count)
                )
            }
        }
    }
}

/// The selection indicator is one persistent glass capsule that slides between
/// segments, positioned by `matchedGeometryEffect` against the segment it is
/// on.
///
/// It deliberately does not toggle `glassEffect` per segment and morph the
/// shapes through a `GlassEffectContainer`. That reads as a moving pill at
/// rest, but it drives the shape through appear/disappear morphs, and
/// `GlassEffectTransition.matchedGeometry` then "applies additional scale and
/// offset effects to content when the identity of the shape does not change
/// but its content does" — the selection ID is constant while the segment
/// under it changes, so every switch picked up that extra scale and offset.
@available(macOS 26.0, *)
private struct LiquidGlassDetailTabPicker<Tab: DetailTab>: View {
    @Binding var selection: Tab

    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Namespace private var glassNamespace

    var body: some View {
        HStack(spacing: DetailTabLayout.segmentGap) {
            ForEach(Tab.allCases) { tab in
                Button {
                    selection = tab
                } label: {
                    Text(tab.rawValue)
                        .font(.system(size: 12))
                        .lineLimit(1)
                        .frame(minWidth: 44, maxWidth: .infinity)
                        .frame(height: 28)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity)
                .foregroundStyle(selection == tab ? .primary : .secondary)
                .matchedGeometryEffect(id: tab, in: glassNamespace, isSource: true)
            }
        }
        .padding(DetailTabLayout.segmentGap)
        .background {
            Color.clear
                .glassEffect(.regular.interactive())
                .matchedGeometryEffect(
                    id: selection,
                    in: glassNamespace,
                    isSource: false
                )
        }
        .frame(
            minWidth: DetailTabLayout.minimumWidth(for: Tab.allCases.count),
            idealWidth: DetailTabLayout.idealWidth(for: Tab.allCases.count),
            maxWidth: DetailTabLayout.idealWidth(for: Tab.allCases.count)
        )
        .animation(
            reduceMotion ? nil : .smooth(duration: 0.2),
            value: selection
        )
        .accessibilityRepresentation {
            Picker("Tab", selection: $selection) {
                ForEach(Tab.allCases) { tab in
                    Text(tab.rawValue).tag(tab)
                }
            }
            .pickerStyle(.segmented)
        }
    }
}

private enum DetailTabLayout {
    /// The gap between two segments, and the inset around the whole bar.
    static let segmentGap: CGFloat = 2

    static func minimumWidth(for count: Int) -> CGFloat {
        count <= 2
            ? 3 * AppMetrics.detailTabSegment
            : CGFloat(count) * AppMetrics.detailTabSegment * 0.7
    }

    static func idealWidth(for count: Int) -> CGFloat {
        CGFloat(max(count, 3)) * AppMetrics.detailTabSegment
    }
}
