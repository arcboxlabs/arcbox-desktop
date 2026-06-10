import SwiftUI

/// Compact used/limit gauge for one runtime pool (e.g. "macOS 1/2").
struct CapacityGauge: View {
    let label: String
    let systemImage: String
    let capacity: RunnerCapacity

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 4) {
                Image(systemName: systemImage)
                    .font(.system(size: 9))
                    .foregroundStyle(AppColors.textSecondary)
                Text(label)
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
                Spacer(minLength: 4)
                Text(capacity.display)
                    .font(.system(size: 11, weight: .medium))
                    .monospacedDigit()
            }
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule()
                        .fill(AppColors.surfaceElevated)
                    Capsule()
                        .fill(capacity.isSaturated ? AppColors.warning : AppColors.accent)
                        .frame(width: geo.size.width * capacity.fraction)
                }
            }
            .frame(height: 4)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(label) capacity \(capacity.used) of \(capacity.limit)")
    }
}
