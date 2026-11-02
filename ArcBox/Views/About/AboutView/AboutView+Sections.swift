import AppKit

extension AboutViewController {
    func headerSection() -> NSView {
        let icon = NSImageView(image: NSApp.applicationIconImage)
        icon.imageScaling = .scaleProportionallyUpOrDown
        icon.setAccessibilityElement(true)
        icon.setAccessibilityRole(.image)
        icon.setAccessibilityLabel("ArcBox application icon")
        NSLayoutConstraint.activate([
            icon.widthAnchor.constraint(equalToConstant: 80),
            icon.heightAnchor.constraint(equalToConstant: 80),
        ])

        let title = label("ArcBox", font: .boldSystemFont(ofSize: 26), alignment: .center)
        let version = label(
            "Version \(appVersion) (\(buildNumber))",
            font: .systemFont(ofSize: 13),
            color: .secondaryLabelColor,
            alignment: .center
        )
        let stack = verticalStack([icon, title, version], spacing: 8)
        stack.alignment = .centerX
        return stack
    }

    func versionInfoSection() -> NSView {
        let values = [
            ("Desktop App", appVersion),
            ("ArcBox Daemon", daemonVersion),
            ("macOS", macOSVersion),
            ("Architecture", architecture),
        ]
        var rows: [NSView] = []
        for (index, value) in values.enumerated() {
            rows.append(infoRow(label: value.0, value: value.1))
            if index < values.count - 1 {
                rows.append(separator())
            }
        }
        let copyButton = NSButton(
            title: "Copy System Info",
            target: self,
            action: #selector(copySystemInfo)
        )
        copyButton.bezelStyle = .inline
        copyButton.image = NSImage(
            systemSymbolName: "doc.on.doc",
            accessibilityDescription: nil
        )
        copyButton.imagePosition = .imageLeading
        copyButton.toolTip = "Copy ArcBox and system version information"
        copyButton.setAccessibilityHelp(copyButton.toolTip)

        return verticalStack([card(containing: verticalStack(rows, spacing: 0)), copyButton], spacing: 6)
    }

    func whatsNewSection() -> NSView {
        changelogContent.alignment = .width
        changelogContent.orientation = .vertical
        changelogContent.translatesAutoresizingMaskIntoConstraints = false
        showReleases([])
        return verticalStack(
            [
                label("What's New", font: .systemFont(ofSize: 13, weight: .semibold)),
                changelogContent,
            ], spacing: 12)
    }

    func showReleases(_ releases: [ChangelogRelease]) {
        for view in changelogContent.arrangedSubviews {
            changelogContent.removeArrangedSubview(view)
            view.removeFromSuperview()
        }
        guard !releases.isEmpty else {
            let empty = label(
                "No changelog available.",
                font: .systemFont(ofSize: 13),
                color: .tertiaryLabelColor,
                alignment: .center
            )
            changelogContent.addArrangedSubview(padded(empty, horizontal: 0, vertical: 20))
            return
        }

        var rows: [NSView] = []
        for (index, release) in releases.prefix(3).enumerated() {
            rows.append(padded(releaseRow(release), horizontal: 12, vertical: 12))
            if index < min(releases.count, 3) - 1 {
                rows.append(padded(separator(), horizontal: 12, vertical: 0))
            }
        }
        rows.append(padded(separator(), horizontal: 12, vertical: 0))
        rows.append(
            padded(
                linkButton(
                    icon: "arrow.up.right",
                    title: "View Full Changelog",
                    url: "https://github.com/arcboxlabs/arcbox-desktop/releases"
                ),
                horizontal: 12,
                vertical: 6
            )
        )
        changelogContent.addArrangedSubview(card(containing: verticalStack(rows, spacing: 0)))
    }

    func helpSection() -> NSView {
        let grid = NSGridView(views: [
            [
                linkButton(icon: "book", title: "Documentation", url: "https://arcbox.link/docs"),
                linkButton(icon: "lifepreserver", title: "Support", url: "https://arcbox.link/dsup"),
            ],
            [
                linkButton(icon: "tag", title: "Release Notes", url: "https://arcbox.link/dreleases"),
                linkButton(
                    icon: "chevron.left.forwardslash.chevron.right",
                    title: "Source Code",
                    url: "https://github.com/arcboxlabs/arcbox-desktop"
                ),
            ],
        ])
        grid.columnSpacing = 8
        grid.rowSpacing = 8
        for index in 0..<grid.numberOfColumns {
            grid.column(at: index).xPlacement = .fill
        }
        return verticalStack(
            [
                label("Help & Support", font: .systemFont(ofSize: 13, weight: .semibold)),
                grid,
            ], spacing: 12)
    }

    func footerSection() -> NSView {
        let year = Calendar.current.component(.year, from: Date())
        let copyright = label(
            "© 2024–\(year) ArcBox Labs. All rights reserved.",
            font: .systemFont(ofSize: 11),
            color: .tertiaryLabelColor,
            alignment: .center
        )
        let notices = NSButton(
            title: "Third-Party Notices",
            target: self,
            action: #selector(showThirdPartyNotices(_:))
        )
        notices.bezelStyle = .inline
        notices.isBordered = false
        notices.font = .systemFont(ofSize: 11)
        notices.contentTintColor = .linkColor
        notices.toolTip = "Licenses and source code of the open-source software in ArcBox"
        notices.setAccessibilityHelp(notices.toolTip)
        let stack = verticalStack([copyright, notices], spacing: 6)
        stack.alignment = .centerX
        return stack
    }

    @objc func showThirdPartyNotices(_ sender: NSButton) {
        showThirdPartyNoticesWindow()
    }

    private func infoRow(label title: String, value: String) -> NSView {
        let titleLabel = label(title, font: .systemFont(ofSize: 13, weight: .medium))
        let valueLabel = label(
            value,
            font: .systemFont(ofSize: 13),
            color: .secondaryLabelColor,
            alignment: .right
        )
        valueLabel.isSelectable = true
        valueLabel.setContentCompressionResistancePriority(.defaultLow, for: .horizontal)

        let row = NSStackView(views: [titleLabel, valueLabel])
        row.alignment = .firstBaseline
        row.distribution = .fill
        row.orientation = .horizontal
        row.spacing = 12
        row.setAccessibilityElement(true)
        row.setAccessibilityRole(.group)
        row.setAccessibilityLabel("\(title): \(value)")
        return padded(row, horizontal: 12, vertical: 8)
    }
}
