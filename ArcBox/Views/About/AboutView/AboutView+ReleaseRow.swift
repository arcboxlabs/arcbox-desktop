import SwiftUI

extension AboutView {
    func releaseRow(_ release: ChangelogRelease) -> some View {
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
}
