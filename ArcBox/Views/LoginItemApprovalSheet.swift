import ArcBoxClient
import OSLog
import ServiceManagement
import SwiftUI

/// Sheet prompting the user to approve ArcBox in System Settings → Login Items.
/// Polls for approval status and shows a success indicator once approved.
struct LoginItemApprovalSheet: View {
    @Environment(HelperManager.self) private var helperManager
    @Environment(\.startupOrchestrator) private var startupOrchestrator
    @Environment(\.dismiss) private var dismiss

    @State private var approved = false
    @State private var pollingTask: Task<Void, Never>?

    var body: some View {
        VStack(spacing: 24) {
            // Icon
            Group {
                if approved {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.green)
                        .transition(.scale.combined(with: .opacity))
                } else {
                    Image(systemName: "person.badge.shield.checkmark.fill")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                }
            }
            .animation(.easeInOut(duration: 0.3), value: approved)

            // Title
            Text(approved ? "Login Item Approved" : "Login Item Approval Required")
                .font(.title3.weight(.semibold))

            // Description
            VStack(spacing: 10) {
                if approved {
                    Text("ArcBox has been granted the required permissions.")
                        .foregroundStyle(.secondary)
                } else {
                    Text("ArcBox needs login item approval to manage background services.")
                        .foregroundStyle(.secondary)

                    Text("System Settings → General → Login Items & Extensions")
                        .fontWeight(.semibold)

                    (Text("Find ") + Text("ArcBox Desktop.app").fontWeight(.semibold) + Text(" in the list and enable it."))
                        .foregroundStyle(.secondary)
                }
            }
            .font(.callout)
            .multilineTextAlignment(.center)
            .frame(maxWidth: 300)

            // Action button
            Button(approved ? "Done" : "Open System Settings") {
                if approved {
                    Task { await startupOrchestrator?.retry() }
                    dismiss()
                } else {
                    helperManager.openSystemSettings()
                    startPolling()
                }
            }
            .keyboardShortcut(.defaultAction)
            .controlSize(.large)
        }
        .padding(32)
        .frame(width: 400, height: 400)
        .overlay(alignment: .topTrailing) {
            if approved {
                Button {
                    Task { await startupOrchestrator?.retry() }
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 16))
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .padding(12)
            }
        }
        .task {
            startPolling()
        }
        .onDisappear {
            pollingTask?.cancel()
        }
    }

    private func startPolling() {
        guard pollingTask == nil, !approved else { return }
        pollingTask = Task {
            let service = SMAppService.daemon(plistName: "com.arcboxlabs.desktop.helper.plist")
            // Poll every 2s for up to 2 minutes
            for _ in 0..<60 {
                try? await Task.sleep(for: .seconds(2))
                if Task.isCancelled { return }
                if service.status != .requiresApproval {
                    // Complete registration before showing success
                    do {
                        try await helperManager.register()
                        withAnimation { approved = true }
                    } catch {
                        Log.helper.error("Register failed after approval: \(error.localizedDescription, privacy: .public)")
                    }
                    break
                }
            }
            pollingTask = nil
        }
    }
}
