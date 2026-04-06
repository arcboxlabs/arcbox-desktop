import SwiftUI

// MARK: - About View

struct AboutView: View {
    @State private var releases: [ChangelogRelease] = []

    // MARK: - System Info

    private var appVersion: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "Unknown"
    }

    private var buildNumber: String {
        Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
    }

    private var daemonVersion: String {
        guard let url = Bundle.main.url(forResource: "arcbox", withExtension: "version"),
            let content = try? String(contentsOf: url, encoding: .utf8)
        else {
            return "Unknown"
        }
        return content.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private var macOSVersion: String {
        let v = ProcessInfo.processInfo.operatingSystemVersion
        return "\(v.majorVersion).\(v.minorVersion).\(v.patchVersion)"
    }

    private var architecture: String {
        #if arch(arm64)
            return "Apple Silicon (arm64)"
        #elseif arch(x86_64)
            return "Intel (x86_64)"
        #else
            return "Unknown"
        #endif
    }

    // MARK: - Body

    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                headerSection
                versionInfoSection
                whatsNewSection
                helpSection
                footerSection
            }
            .padding(24)
        }
        .task {
            let loadedReleases = await Task.detached(priority: .utility) {
                ChangelogParser.loadFromBundle(limit: 3)
            }.value

            await MainActor.run {
                releases = loadedReleases
            }
        }
    }

    // MARK: - Header

    private var headerSection: some View {
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

    // MARK: - Version Info

    private var versionInfoSection: some View {
        VStack(spacing: 0) {
            InfoRow(label: "Desktop App", value: appVersion)
            InfoRow(label: "ArcBox Daemon", value: daemonVersion)
            InfoRow(label: "macOS", value: macOSVersion)
            InfoRow(label: "Architecture", value: architecture)
        }
        .infoSectionStyle()
    }

    // MARK: - What's New

    @ViewBuilder
    private var whatsNewSection: some View {
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

    private func releaseRow(_ release: ChangelogRelease) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 6) {
                Text(release.version)
                    .font(.system(size: 13, weight: .semibold))
                Text("·")
                    .foregroundStyle(AppColors.textMuted)
                Text(release.date)
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary)
            }

            ForEach(release.sections) { section in
                VStack(alignment: .leading, spacing: 4) {
                    Text(section.title)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(AppColors.textSecondary)
                        .textCase(.uppercase)

                    ForEach(section.items, id: \.self) { item in
                        HStack(alignment: .top, spacing: 6) {
                            Text("•")
                                .foregroundStyle(AppColors.textMuted)
                            Text(item)
                                .font(.system(size: 12))
                                .foregroundStyle(AppColors.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
            }
        }
    }

    // MARK: - Help & Support

    private var helpSection: some View {
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

    private func linkButton(icon: String, title: String, url: String) -> some View {
        Button {
            guard let destination = URL(string: url) else { return }
            NSWorkspace.shared.open(destination)
        } label: {
            HStack(spacing: 8) {
                Image(systemName: icon)
                    .font(.system(size: 14))
                    .frame(width: 20)
                Text(title)
                    .font(.system(size: 12))
                Spacer()
                Image(systemName: "arrow.up.right")
                    .font(.system(size: 9))
                    .foregroundStyle(AppColors.textMuted)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 10)
            .background(AppColors.surfaceCard)
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .stroke(AppColors.border, lineWidth: 0.5)
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - Footer

    private var footerSection: some View {
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

#Preview {
    AboutView()
        .frame(width: 500, height: 660)
}
