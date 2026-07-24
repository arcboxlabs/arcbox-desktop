import SwiftUI

struct RunnerJobInfoTab: View {
    let job: RunnerJobDetailModel

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                overviewSection
                assignmentSection
                timelineSection
                labelsSection
            }
            .padding(16)
        }
    }

    private var overviewSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Job")
                .font(.headline)

            VStack(spacing: 0) {
                InfoRow(label: "Status", value: job.status.displayName)
                InfoRow(label: "Repository", value: job.repository ?? "Waiting for Platform")
                InfoRow(label: "Job ID", value: job.id)
                InfoRow(label: "Target", value: "\(job.os)/\(job.arch)")
                InfoRow(
                    label: "GitHub run ID",
                    value: job.githubRunID?.formatted() ?? "Waiting for Platform",
                    link: job.githubURL
                )
                InfoRow(
                    label: "GitHub job ID",
                    value: job.githubJobID?.formatted() ?? "Waiting for Platform",
                    link: job.githubURL
                )
            }
            .infoSectionStyle()
        }
    }

    private var assignmentSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Assignment")
                .font(.headline)

            VStack(spacing: 0) {
                InfoRow(label: "Fleet machine ID", value: job.machineID ?? "Not reported")
                InfoRow(label: "JIT runner", value: job.jitRunnerName ?? "Not reported")
                InfoRow(label: "Runtime type", value: job.runtimeKind)
            }
            .infoSectionStyle()
        }
    }

    private var timelineSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Timeline")
                .font(.headline)

            VStack(spacing: 0) {
                InfoRow(label: "Created", value: dateDescription(job.createdAt))
                InfoRow(label: "Started", value: dateDescription(job.startedAt))
                InfoRow(label: "Finished", value: dateDescription(job.finishedAt))
            }
            .infoSectionStyle()
        }
    }

    @ViewBuilder
    private var labelsSection: some View {
        if job.labels.isEmpty {
            VStack(alignment: .leading, spacing: 8) {
                Text("Labels")
                    .font(.headline)

                VStack(spacing: 0) {
                    InfoRow(label: "Runner labels", value: "None reported")
                }
                .infoSectionStyle()
            }
        } else {
            InfoTableView(
                title: "Labels",
                columns: ["Runner label"],
                items: job.labels.enumerated().map(RunnerJobLabel.init)
            ) { label in
                Text(label.value)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
            }
        }
    }

    private func dateDescription(_ date: Date?) -> String {
        date?.formatted(date: .abbreviated, time: .standard) ?? "Not reported"
    }
}

private struct RunnerJobLabel: Identifiable {
    let id: Int
    let value: String

    init(_ entry: EnumeratedSequence<[String]>.Element) {
        id = entry.offset
        value = entry.element
    }
}
