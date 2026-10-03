import AppKit
import SwiftUI

struct OnboardingMigrationPage: View {
    let state: OnboardingMigrationModel.State

    @AccessibilityFocusState private var headingFocused: Bool

    var body: some View {
        Group {
            switch state {
            case .idle, .checking:
                checkingPage
            case .unavailable:
                unavailablePage
            case .empty(let source):
                emptyPage(source)
            case .review(let preview):
                reviewPage(preview)
            case .preparing:
                progressPage(
                    title: "Preparing migration",
                    message: "ArcBox is creating an executable migration plan.",
                    progress: nil
                )
            case .migrating(_, let progress):
                progressPage(
                    title: "Migrating your Docker environment",
                    message: progress.message,
                    progress: progress
                )
            case .completed(_, let warnings):
                completedPage(warnings: warnings)
            case .failed(_, let message):
                failedPage(message: message)
            }
        }
        .frame(maxWidth: 536)
        .onAppear {
            headingFocused = true
        }
        .onChange(of: pageIdentity) {
            headingFocused = true
        }
    }

    private var checkingPage: some View {
        VStack(spacing: 16) {
            ProgressView()
                .controlSize(.large)

            pageTitle("Checking your Docker environment")

            Text("Looking for workloads that can be brought into ArcBox.")
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private var unavailablePage: some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textSecondary)
                .accessibilityHidden(true)

            pageTitle("No Docker environment to migrate")

            Text("You can start using ArcBox now.")
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private func emptyPage(_ source: DockerMigrationSource) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "shippingbox")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.textSecondary)
                .accessibilityHidden(true)

            pageTitle("Nothing to migrate")

            Text("No supported resources were found in \(source.kind.displayName).")
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private func reviewPage(_ preview: OnboardingMigrationPreview) -> some View {
        VStack(spacing: 14) {
            Image(systemName: "shippingbox.and.arrow.backward")
                .font(.system(size: 42))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            VStack(spacing: 5) {
                pageTitle("Import your Docker environment")

                Text(
                    "ArcBox found \(preview.totalResourceCount) "
                        + "resource\(preview.totalResourceCount == 1 ? "" : "s") "
                        + "in \(preview.source.kind.displayName)."
                )
                .font(.system(size: 14))
                .foregroundStyle(AppColors.textSecondary)

                if !preview.daemonName.isEmpty || !preview.serverVersion.isEmpty {
                    Text(
                        [preview.daemonName, preview.serverVersion]
                            .filter { !$0.isEmpty }
                            .joined(separator: " · ")
                    )
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textMuted)
                }
            }

            HStack(spacing: 8) {
                MigrationCountView("Images", count: preview.imageCount, symbol: "shippingbox")
                MigrationCountView("Volumes", count: preview.volumeCount, symbol: "externaldrive")
                MigrationCountView("Networks", count: preview.networkCount, symbol: "network")
                MigrationCountView(
                    "Containers",
                    count: preview.containerCount,
                    symbol: "cube"
                )
            }

            VStack(alignment: .leading, spacing: 8) {
                Text("ArcBox copies supported resources without deleting them from the source.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if !preview.confirmationMessages.isEmpty {
                    MigrationNotice(
                        title: "Your confirmation is required",
                        symbol: "exclamationmark.shield.fill",
                        color: AppColors.warning,
                        messages: preview.confirmationMessages
                    )
                }

                if !preview.unsupportedResources.isEmpty {
                    MigrationNotice(
                        title: "Resolve before migrating",
                        symbol: "xmark.octagon.fill",
                        color: AppColors.error,
                        messages: preview.unsupportedResources
                    )
                } else if !preview.warnings.isEmpty {
                    MigrationNotice(
                        title: "Review before migrating",
                        symbol: "exclamationmark.triangle.fill",
                        color: AppColors.warning,
                        messages: preview.warnings
                    )
                }
            }
            .padding(14)
            .background(cardBackground)
            .overlay(cardBorder)
        }
    }

    private func progressPage(
        title: String,
        message: String,
        progress: OnboardingMigrationProgress?
    ) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "arrow.triangle.2.circlepath")
                .font(.system(size: 44))
                .foregroundStyle(Color.accentColor)
                .symbolEffect(.rotate)
                .accessibilityHidden(true)

            pageTitle(title)

            VStack(spacing: 8) {
                if let fraction = progress?.fractionCompleted {
                    ProgressView(value: fraction)
                } else {
                    ProgressView()
                }

                Text(message.isEmpty ? "Working…" : message)
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                    .multilineTextAlignment(.center)
                    .onChange(of: message) { _, newMessage in
                        announceProgress(newMessage)
                    }

                if let progress {
                    let detail = [progress.phase, progress.resource]
                        .filter { !$0.isEmpty }
                        .joined(separator: " · ")
                    if !detail.isEmpty {
                        Text(detail)
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.textMuted)
                    }
                }
            }
            .frame(width: 420)
        }
    }

    private func completedPage(warnings: [String]) -> some View {
        VStack(spacing: 16) {
            Image(systemName: warnings.isEmpty ? "checkmark.circle.fill" : "checkmark.circle")
                .font(.system(size: 52))
                .foregroundStyle(warnings.isEmpty ? AppColors.running : AppColors.warning)
                .accessibilityHidden(true)

            pageTitle(
                warnings.isEmpty ? "Migration complete" : "Migration completed with warnings"
            )

            if warnings.isEmpty {
                Text("Your Docker resources are ready in ArcBox.")
                    .font(.system(size: 14))
                    .foregroundStyle(AppColors.textSecondary)
            } else {
                MigrationNotice(
                    title: "Needs attention",
                    symbol: "exclamationmark.triangle.fill",
                    color: AppColors.warning,
                    messages: warnings
                )
                .padding(14)
                .background(cardBackground)
                .overlay(cardBorder)
            }
        }
    }

    private func failedPage(message: String) -> some View {
        VStack(spacing: 16) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 48))
                .foregroundStyle(AppColors.warning)
                .accessibilityHidden(true)

            pageTitle("Migration could not be completed")

            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var cardBackground: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .fill(AppColors.surfaceCard)
    }

    private var cardBorder: some View {
        RoundedRectangle(cornerRadius: 14, style: .continuous)
            .stroke(AppColors.borderSubtle, lineWidth: 1)
    }

    private var pageIdentity: PageIdentity {
        switch state {
        case .idle, .checking: .checking
        case .unavailable: .unavailable
        case .empty: .empty
        case .review: .review
        case .preparing: .preparing
        case .migrating: .migrating
        case .completed: .completed
        case .failed: .failed
        }
    }

    private func pageTitle(_ title: String) -> some View {
        Text(title)
            .font(.system(size: 24, weight: .semibold))
            .accessibilityAddTraits(.isHeader)
            .accessibilityFocused($headingFocused)
    }

    private func announceProgress(_ message: String) {
        guard !message.isEmpty, let application = NSApp else { return }
        NSAccessibility.post(
            element: application,
            notification: .announcementRequested,
            userInfo: [
                .announcement: message,
                .priority: NSAccessibilityPriorityLevel.low.rawValue,
            ]
        )
    }

    private enum PageIdentity: Hashable {
        case checking
        case unavailable
        case empty
        case review
        case preparing
        case migrating
        case completed
        case failed
    }
}

private struct MigrationCountView: View {
    let title: String
    let count: UInt32
    let symbol: String

    init(_ title: String, count: UInt32, symbol: String) {
        self.title = title
        self.count = count
        self.symbol = symbol
    }

    var body: some View {
        VStack(spacing: 5) {
            Image(systemName: symbol)
                .font(.system(size: 16, weight: .medium))
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)
            Text(count.formatted())
                .font(.system(size: 16, weight: .semibold))
            Text(title)
                .font(.system(size: 10))
                .foregroundStyle(AppColors.textSecondary)
        }
        .frame(maxWidth: .infinity, minHeight: 66)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(AppColors.surfaceCard)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(AppColors.borderSubtle, lineWidth: 1)
        )
        .accessibilityElement(children: .combine)
    }
}

private struct MigrationNotice: View {
    let title: String
    let symbol: String
    let color: Color
    let messages: [String]

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(title, systemImage: symbol)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(color)

            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    ForEach(Array(messages.enumerated()), id: \.offset) { _, message in
                        Text("• \(message)")
                            .font(.system(size: 11))
                            .foregroundStyle(AppColors.textSecondary)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            .frame(maxHeight: 76)
        }
    }
}
