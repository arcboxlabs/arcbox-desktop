import AppKit
import SwiftUI

/// Lists the bundled open-source components and shows each one's license text
/// and where its source code is published.
struct ThirdPartyNoticesView: View {
    let notices: ThirdPartyNotices
    @State private var selection: ThirdPartyNoticeComponent.ID?

    var body: some View {
        NavigationSplitView {
            List(selection: $selection) {
                ForEach(notices.groups) { group in
                    Section(group.title) {
                        ForEach(group.components) { component in
                            VStack(alignment: .leading, spacing: 2) {
                                Text(component.name)
                                    .lineLimit(1)
                                Text(component.license)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(1)
                            }
                            .padding(.vertical, 2)
                        }
                    }
                }
            }
            .listStyle(.sidebar)
            .navigationSplitViewColumnWidth(260)
        } detail: {
            if let selected {
                ThirdPartyNoticeDetail(
                    group: selected.group, component: selected.component, directory: notices.directory)
            } else {
                ThirdPartyNoticesOverview()
            }
        }
        // The window takes the hosting view's ideal size when its controller is
        // assigned; without one the split view starts narrow and keeps its
        // sidebar at that width when the window grows.
        .frame(minWidth: 680, idealWidth: 900, minHeight: 420, idealHeight: 600)
    }

    private var selected: (group: ThirdPartyNoticeGroup, component: ThirdPartyNoticeComponent)? {
        for group in notices.groups {
            if let component = group.components.first(where: { $0.id == selection }) {
                return (group, component)
            }
        }
        return nil
    }
}

private struct ThirdPartyNoticesOverview: View {
    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Third-Party Notices")
                .font(.title2.weight(.semibold))
            Text(
                """
                ArcBox includes open-source software. Each component is distributed under its own \
                license. Choose a component to see its version, its license, and where its source code \
                is published.
                """
            )
            .foregroundStyle(.secondary)
        }
        .frame(maxWidth: 480, alignment: .leading)
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ThirdPartyNoticeDetail: View {
    let group: ThirdPartyNoticeGroup
    let component: ThirdPartyNoticeComponent
    let directory: URL
    @State private var licenseText = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                Text(component.name)
                    .font(.title2.weight(.semibold))
                Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 12, verticalSpacing: 6) {
                    field("Version", component.version)
                    field("License", component.license)
                    if let location = group.location {
                        field("Included in", location)
                    }
                    if let source = component.source {
                        GridRow {
                            fieldLabel("Source")
                            Link(source.absoluteString, destination: source)
                                .lineLimit(1)
                                .truncationMode(.middle)
                        }
                    }
                }
                ForEach([group.summary, component.notes].compactMap(\.self), id: \.self) { paragraph in
                    Text(paragraph)
                        .foregroundStyle(.secondary)
                        .textSelection(.enabled)
                }
            }
            .padding(20)
            Divider()
            if component.licenseFiles.isEmpty {
                Text("This entry has no separate license text; see the description above.")
                    .foregroundStyle(.secondary)
                    .padding(20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            } else {
                LicenseTextView(text: licenseText)
            }
        }
        .task(id: component.id) {
            licenseText = await ThirdPartyNotices.licenseText(of: component, in: directory)
        }
    }

    private func field(_ label: String, _ value: String) -> some View {
        GridRow {
            fieldLabel(label)
            Text(value)
                .textSelection(.enabled)
        }
    }

    private func fieldLabel(_ label: String) -> some View {
        Text(label)
            .foregroundStyle(.secondary)
            .gridColumnAlignment(.trailing)
    }
}

/// A read-only, selectable monospaced text view. AppKit lays out the 600 KB
/// Rust crate notice in a few milliseconds; a SwiftUI `Text` cannot.
private struct LicenseTextView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSTextView.scrollableTextView()
        scrollView.drawsBackground = false
        if let textView = scrollView.documentView as? NSTextView {
            textView.isEditable = false
            textView.isSelectable = true
            textView.drawsBackground = false
            textView.font = .monospacedSystemFont(ofSize: 11, weight: .regular)
            textView.textColor = .labelColor
            textView.textContainerInset = NSSize(width: 14, height: 14)
        }
        return scrollView
    }

    func updateNSView(_ scrollView: NSScrollView, context: Context) {
        guard let textView = scrollView.documentView as? NSTextView, textView.string != text else { return }
        textView.string = text
        textView.scrollToBeginningOfDocument(nil)
    }
}
