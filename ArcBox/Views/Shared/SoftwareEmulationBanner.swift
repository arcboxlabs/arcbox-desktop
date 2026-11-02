import ArcBoxClient
import SwiftUI

/// Stays above the main window's content for as long as the System VM runs under
/// software emulation, so slow starts and slow containers have a visible cause.
struct SoftwareEmulationBanner: View {
    @Environment(DaemonManager.self) private var daemon

    var body: some View {
        if daemon.isSoftwareEmulated {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: "cpu")
                    .foregroundStyle(AppColors.warning)
                    .accessibilityHidden(true)
                VStack(alignment: .leading, spacing: 4) {
                    Text("Software emulation").font(.headline)
                    Text(message).font(.callout)
                }
                Spacer(minLength: 0)
            }
            .padding(12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(AppColors.warning.opacity(0.1))
            .accessibilityElement(children: .combine)
        }
    }

    private var message: String {
        let cause =
            daemon.hardwareVirtualizationAvailable == false
            ? "This Mac doesn't provide hardware virtualization, so ArcBox emulates its Linux VM."
            : "The System VM backend is set to software emulation."
        return cause + " Starting and running containers takes noticeably longer."
    }
}
