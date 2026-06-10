import SwiftUI

/// Persistent host header at the top of the Runners column: enrollment status,
/// fleet routing, per-runtime capacity, and the drain switch.
struct RunnerHostStatusBar: View {
    let host: RunnerHostViewModel
    @Binding var isDraining: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                StatusBadge(color: host.status.color, label: host.status.label)
                Spacer()
                Toggle("Drain", isOn: $isDraining)
                    .toggleStyle(.switch)
                    .controlSize(.mini)
                    .font(.system(size: 11))
                    .disabled(host.status == .offline)
                    .help("Finish running jobs but accept no new ones")
            }

            VStack(alignment: .leading, spacing: 2) {
                Text("\(host.fleetName) · \(host.orgsDisplay)")
                    .font(.system(size: 11))
                    .foregroundStyle(AppColors.textSecondary)
                    .lineLimit(1)
                Text("Last seen \(host.lastSeenAt, format: .relative(presentation: .named))")
                    .font(.system(size: 10))
                    .foregroundStyle(AppColors.textMuted)
            }

            HStack(spacing: 12) {
                CapacityGauge(label: "macOS", systemImage: "macwindow", capacity: host.macOSPool)
                CapacityGauge(label: "Linux", systemImage: "shippingbox", capacity: host.linuxPool)
            }
        }
        .padding(10)
        .background(AppColors.surfaceCard)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(AppColors.border, lineWidth: 0.5))
        .padding(8)
    }
}
