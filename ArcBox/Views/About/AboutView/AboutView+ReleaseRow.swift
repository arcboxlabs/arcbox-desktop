import AppKit

extension AboutViewController {
    func releaseRow(_ release: ChangelogRelease) -> NSView {
        let version = label(release.version, font: .systemFont(ofSize: 13, weight: .semibold))
        let separator = label("·", font: .systemFont(ofSize: 12), color: .tertiaryLabelColor)
        let date = label(
            release.date,
            font: .systemFont(ofSize: 12),
            color: .secondaryLabelColor
        )
        let heading = NSStackView(views: [version, separator, date])
        heading.alignment = .firstBaseline
        heading.orientation = .horizontal
        heading.spacing = 6

        var views: [NSView] = [heading]
        if let highlights = release.highlights {
            let summary = label(
                highlights,
                font: .systemFont(ofSize: 12),
                color: .secondaryLabelColor
            )
            summary.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)
            views.append(summary)
        } else {
            for section in release.sections {
                views.append(releaseSection(section))
            }
        }
        let row = verticalStack(views, spacing: 8)
        row.setAccessibilityElement(true)
        row.setAccessibilityRole(.group)
        row.setAccessibilityLabel("\(release.version), \(release.date)")
        return row
    }

    private func releaseSection(_ section: ChangelogSection) -> NSView {
        let title = label(
            section.title.uppercased(),
            font: .systemFont(ofSize: 11, weight: .medium),
            color: .secondaryLabelColor
        )
        let items = section.items.map { item in
            let bullet = label("•", font: .systemFont(ofSize: 12), color: .tertiaryLabelColor)
            let text = label(item, font: .systemFont(ofSize: 12), color: .secondaryLabelColor)
            text.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

            let row = NSStackView(views: [bullet, text])
            row.alignment = .top
            row.orientation = .horizontal
            row.spacing = 6
            return row
        }
        return verticalStack([title] + items, spacing: 4)
    }
}
