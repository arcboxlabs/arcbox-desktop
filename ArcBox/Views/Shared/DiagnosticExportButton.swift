import AppKit
import ArcBoxClient
import SwiftUI

struct DiagnosticExportButton: View {
    @Environment(DaemonManager.self) private var daemonManager
    @Environment(ContainersViewModel.self) private var containersVM
    @Environment(ImagesViewModel.self) private var imagesVM
    @State private var isExportingDiagnostics = false
    @State private var diagnosticErrorMessage: String?

    var body: some View {
        Group {
            Button("Export Diagnostic Report...") {
                guard let presentingWindow = NSApp.keyWindow ?? NSApp.mainWindow else {
                    diagnosticErrorMessage =
                        "ArcBox could not present the save panel. Reopen Settings and try again."
                    return
                }
                diagnosticErrorMessage = nil
                isExportingDiagnostics = true
                Task {
                    defer { isExportingDiagnostics = false }
                    do {
                        _ = try await DiagnosticBundleExporter.exportInteractively(
                            daemonManager: daemonManager,
                            containersVM: containersVM,
                            imagesVM: imagesVM,
                            presentingWindow: presentingWindow
                        )
                    } catch {
                        diagnosticErrorMessage =
                            "Diagnostic report was not exported: \(error.localizedDescription)"
                    }
                }
            }
            .disabled(isExportingDiagnostics)

            if isExportingDiagnostics {
                HStack {
                    ProgressView().controlSize(.small)
                    Text("Generating report...")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }

            if let diagnosticErrorMessage {
                Label(diagnosticErrorMessage, systemImage: "exclamationmark.triangle")
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        }
    }
}
