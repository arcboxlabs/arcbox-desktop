import AppKit
import SwiftUI

extension AboutView {
    var headerSection: some View {
        VStack(spacing: 8) {
            Image(nsImage: NSApp.applicationIconImage)
                .resizable()
                .frame(width: 80, height: 80)

            Text("ArcBox")
                .font(.title)
                .fontWeight(.bold)

            Text(verbatim: "Version \(appVersion) (\(buildNumber))")
                .font(.subheadline)
                .foregroundStyle(AppColors.textSecondary)
        }
        .padding(.top, 8)
    }

    var versionInfoSection: some View {
        VStack(spacing: 0) {
            InfoRow(label: "Desktop App", value: appVersion)
            InfoRow(label: "ArcBox Daemon", value: daemonVersion)
            InfoRow(label: "macOS", value: macOSVersion)
            InfoRow(label: "Architecture", value: architecture)
        }
        .infoSectionStyle()
    }

    @ViewBuilder
    var whatsNewSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("What's New")
                .font(.headline)
                .padding(.horizontal, 4)

            if releases.isEmpty {
                Text("No changelog available.")
                    .font(.subheadline)
                    .foregroundStyle(AppColors.textMuted)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 20)
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(releases.prefix(3).enumerated()), id: \.element.id) { index, release in
                        releaseRow(release)
                            .padding(12)

                        if index < min(releases.count, 3) - 1 {
                            Divider().opacity(0.3).padding(.horizontal, 12)
                        }
                    }

                    Divider().opacity(0.3).padding(.horizontal, 12)

                    Button {
                        if let url = URL(string: "https://github.com/arcboxlabs/arcbox-desktop/releases") {
                            NSWorkspace.shared.open(url)
                        }
                    } label: {
                        HStack {
                            Spacer()
                            Text("View Full Changelog")
                            Image(systemName: "arrow.up.right")
                                .font(.caption)
                            Spacer()
                        }
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                    .foregroundStyle(AppColors.accent)
                }
                .infoSectionStyle()
            }
        }
    }

    var helpSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Help & Support")
                .font(.headline)
                .padding(.horizontal, 4)

            // Short links managed via arcbox.link / git.new:
            //   arcbox.link/docs      → https://docs.arcbox.dev
            //   arcbox.link/dsup      → https://github.com/arcboxlabs/arcbox-desktop/issues
            //   arcbox.link/dreleases → https://github.com/arcboxlabs/arcbox-desktop/releases
            //   git.new/orbstack      → https://github.com/arcboxlabs/arcbox-desktop
            LazyVGrid(columns: [GridItem(.flexible()), GridItem(.flexible())], spacing: 8) {
                linkButton(icon: "book", title: "Documentation", url: "https://arcbox.link/docs")
                linkButton(
                    icon: "lifepreserver", title: "Support",
                    url: "https://arcbox.link/dsup"
                )
                linkButton(
                    icon: "tag", title: "Release Notes",
                    url: "https://arcbox.link/dreleases"
                )
                linkButton(
                    icon: "chevron.left.forwardslash.chevron.right", title: "Source Code",
                    url: "https://git.new/orbstack"
                )
            }
        }
    }

    var footerSection: some View {
        VStack(spacing: 6) {
            let year = Calendar.current.component(.year, from: Date())
            Text(verbatim: "© 2024–\(year) ArcBox Labs. All rights reserved.")
                .font(.system(size: 11))
                .foregroundStyle(AppColors.textMuted)

            Button("Acknowledgements") {
                // TODO(ABXD): Show acknowledgements for open-source dependencies
            }
            .buttonStyle(.plain)
            .font(.system(size: 11))
            .foregroundStyle(AppColors.textMuted)
            .disabled(true)
        }
        .padding(.top, 8)
    }
}
