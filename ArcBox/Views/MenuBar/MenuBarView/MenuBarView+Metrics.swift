import SwiftUI

extension MenuBarView {
    // MARK: - Metric Cards

    var metricCards: some View {
        HStack(spacing: 6) {
            metricCard(
                title: "Volumes",
                count: volumesVM.volumes.count,
                symbol: "internaldrive",
                tint: .mint
            ) {
                navigateToPage(.volumes)
            }

            metricCard(
                title: "Images",
                count: imagesVM.images.count,
                symbol: "circle.circle",
                tint: .indigo
            ) {
                navigateToPage(.images)
            }

            metricCard(
                title: "Networks",
                count: networksVM.networks.count,
                symbol: "point.3.filled.connected.trianglepath.dotted",
                tint: .cyan
            ) {
                navigateToPage(.networks)
            }
        }
        .padding(.bottom, 2)
    }

    func metricCard(
        title: String,
        count: Int,
        symbol: String,
        tint: Color,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                HStack(spacing: 4) {
                    Image(systemName: symbol)
                        .font(.caption2)
                        .foregroundStyle(tint)
                    Text(title)
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 0)

                Text("\(count)")
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundStyle(tint)
                    .frame(maxWidth: .infinity, alignment: .center)

                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(8)
            .frame(height: 70)
            .background(
                RoundedRectangle(cornerRadius: 8, style: .continuous)
                    .fill(.quaternary.opacity(0.30))
            )
        }
        .buttonStyle(.plain)
    }

}
