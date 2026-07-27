import FleetControlClient
import FleetPlatformClient
import SwiftUI

struct RunnerHostCapacityTab: View {
    let host: RunnerHostViewModel
    let machine: FleetMachine?

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                poolSection(
                    title: "macOS runners",
                    pool: .macOS,
                    policyLimit: "Up to 2 concurrent VMs"
                )
                poolSection(
                    title: "Linux runners",
                    pool: .linux
                )
                hardwareSection
            }
            .padding(16)
        }
    }

    private func poolSection(
        title: String,
        pool: RunnerPoolOS,
        policyLimit: String? = nil
    ) -> some View {
        let capabilities = host.capabilities(for: pool)

        return VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.headline)

            VStack(spacing: 0) {
                InfoRow(
                    label: "Availability",
                    value: capabilities.isEmpty ? "Not reported" : "Available"
                )
                InfoRow(
                    label: "Active jobs",
                    value: host.activeJobCount(for: pool).formatted()
                )
                InfoRow(
                    label: policyLimit == nil ? "Concurrency limit" : "Policy limit",
                    value: policyLimit ?? "Not reported by Agent"
                )
                InfoRow(
                    label: "Backends",
                    value: capabilities.isEmpty
                        ? "None"
                        : unique(capabilities.map { $0.backend.displayName }).joined(separator: ", ")
                )
                InfoRow(
                    label: "Architectures",
                    value: capabilities.isEmpty
                        ? "None"
                        : unique(capabilities.map(\.arch)).joined(separator: ", ")
                )
            }
            .infoSectionStyle()
        }
    }

    private func unique(_ values: [String]) -> [String] {
        Array(Set(values)).sorted()
    }

    private var hardwareSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Host resources")
                .font(.headline)

            VStack(spacing: 0) {
                InfoRow(label: "CPU", value: cpuDescription)
                InfoRow(label: "Memory", value: memoryDescription)
                InfoRow(label: "Available memory", value: availableMemoryDescription)
                InfoRow(label: "1-minute load", value: loadDescription)
            }
            .infoSectionStyle()
        }
    }

    private var cpuDescription: String {
        if let cpuCount = host.telemetry?.cpuCount {
            return "\(cpuCount) cores"
        }
        if let cpu = machine?.cpu {
            return "\(cpu) cores"
        }
        return "Unavailable"
    }

    private var memoryDescription: String {
        if let total = host.telemetry?.memoryTotalMib {
            return "\(total.formatted()) MiB"
        }
        if let total = machine?.memMib {
            return "\(total.formatted()) MiB"
        }
        return "Unavailable"
    }

    private var availableMemoryDescription: String {
        guard let available = host.telemetry?.memoryAvailableMib else {
            return "Unavailable"
        }
        return "\(available.formatted()) MiB"
    }

    private var loadDescription: String {
        guard let load = host.telemetry?.loadAverage1Minute else {
            return "Unavailable"
        }
        return load.formatted(.number.precision(.fractionLength(2)))
    }
}
