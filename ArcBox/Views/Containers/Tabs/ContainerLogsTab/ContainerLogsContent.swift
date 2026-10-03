import SwiftUI

/// The log lines, or the placeholder that stands in for them.
///
/// This is the one view a batch of appended lines re-evaluates.
struct ContainerLogsContent: View {
    let model: ContainerLogsModel

    /// The zero-height view after the last row that following scrolls to. It
    /// sits outside the lazy stack on purpose: resolving a row's id makes
    /// SwiftUI walk every item of the `ForEach` (`LazyStack.firstIndex(of:)`),
    /// which is what made a batch cost grow with the buffer — 20 ms at 6,000
    /// lines against 11 ms at 600 — while a plain view's frame is on record.
    static let endID = "end-of-log"

    var body: some View {
        VStack(spacing: 0) {
            if model.isLoading && model.logEntries.isEmpty {
                Spacer()
                ProgressView("Loading logs...")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
            } else if let error = model.errorMessage, model.logEntries.isEmpty {
                Spacer()
                VStack(spacing: 8) {
                    Image(systemName: "exclamationmark.triangle")
                        .font(.system(size: 24))
                        .foregroundStyle(AppColors.textMuted)
                        .accessibilityHidden(true)
                    Text(error)
                        .font(.system(size: 13))
                        .foregroundStyle(AppColors.textSecondary)
                }
                Spacer()
            } else if model.filteredEntries.isEmpty {
                Spacer()
                Text(model.logEntries.isEmpty ? "No logs available" : "No matching logs")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                Spacer()
            } else {
                logList
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .recordingBodyEvaluation(of: Self.self)
    }

    private var logList: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(spacing: 0) {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(model.filteredEntries) { entry in
                            ContainerLogsRow(entry: entry)
                        }
                    }
                    .padding(.vertical, 4)
                    Color.clear
                        .frame(height: 0)
                        .id(Self.endID)
                }
            }
            // Historical logs open at their last line.
            .defaultScrollAnchor(.bottom, for: .initialOffset)
            // Keyed on the last line, not the count: at the buffer cap a batch trims
            // as many lines as it appends and the count stands still, and the view
            // would drift off the end. Unanimated: animating a jump to the end makes
            // SwiftUI walk the list to resolve the target, and a followed container
            // pays that on every line.
            .onChange(of: model.logEntries.last?.id) {
                if model.isFollowing {
                    scrollToEnd(proxy)
                }
            }
            .onChange(of: model.isFollowing) { _, isFollowing in
                if isFollowing {
                    scrollToEnd(proxy)
                }
            }
        }
    }

    /// The one place the content scrolls. The end marker is the only target it ever
    /// asks for; the batch test holds it to that.
    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        #if DEBUG
            ContainerLogsDiagnostics.recordScroll(to: Self.endID)
        #endif
        proxy.scrollTo(Self.endID, anchor: .bottom)
    }
}
