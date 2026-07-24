import SwiftUI

struct RunnerJobRuntimeTab: View {
    let job: RunnerJobDetailModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                targetSection
                runtimeSection
            }
            .padding(16)
        }
    }

    private var targetSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Execution target")
                .font(.headline)

            VStack(spacing: 0) {
                InfoRow(label: "Operating system", value: job.os)
                InfoRow(label: "Architecture", value: job.arch)
                InfoRow(label: "Runtime type", value: job.runtimeKind)
                InfoRow(label: "Fleet machine ID", value: job.machineID ?? "Not reported")
                InfoRow(label: "JIT runner", value: job.jitRunnerName ?? "Not reported")
            }
            .infoSectionStyle()
        }
    }

    private var runtimeSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Runtime resource")
                .font(.headline)

            VStack(spacing: 0) {
                InfoRow(label: "Resource ID", value: "Not reported")
                InfoRow(label: "ArcBox section", value: destinationSection)
            }
            .infoSectionStyle()

            Label(job.runtimeUnavailableDescription, systemImage: "info.circle")
                .font(.caption)
                .foregroundStyle(AppColors.textSecondary)
        }
    }

    private var destinationSection: String {
        switch job.os {
        case "darwin", "macos":
            "Machines"
        case "linux":
            "Containers"
        default:
            "Unavailable"
        }
    }
}
