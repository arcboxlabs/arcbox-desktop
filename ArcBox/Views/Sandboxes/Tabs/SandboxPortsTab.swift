import ArcBoxClient
import SwiftUI

/// Ports tab: expose sandbox ports on the host (loopback) and remove mappings.
///
/// The tab composes leaves that each observe only what they render:
/// `SandboxPortsToolbar` (the expose form, with its segmented protocol picker)
/// and `SandboxPortsContent` (the mapping list). A refresh flips the view
/// model's load state and replaces the mapping list; neither reaches the
/// toolbar, so its `NSSegmentedControl` — whose every measurement re-runs its
/// own view graph — is never re-measured by one.
struct SandboxPortsTab: View {
    let sandbox: SandboxViewModel

    @Environment(SandboxesViewModel.self) private var vm
    @Environment(DaemonManager.self) private var daemonManager
    @Environment(\.arcboxClient) private var client

    @State private var form: SandboxPortsForm
    /// Set while an expose or unexpose call is in flight; the leaves disable
    /// their actions on it.
    @State private var isWorking = false

    /// `form` is the seam the relayout regression tests read the picker's
    /// protocol back through.
    init(sandbox: SandboxViewModel, form: SandboxPortsForm = SandboxPortsForm()) {
        self.sandbox = sandbox
        _form = State(initialValue: form)
    }

    var body: some View {
        VStack(spacing: 0) {
            SandboxPortsToolbar(sandboxID: sandbox.id, form: form, isWorking: $isWorking)
            Divider()
            SandboxPortsContent(sandboxID: sandbox.id, isWorking: $isWorking)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .task(
            id: PortLoadID(
                sandboxID: sandbox.id,
                client: client.map(ObjectIdentifier.init),
                runtimeReady: daemonManager.canExposePorts
            )
        ) {
            await vm.loadExposedPorts(
                for: sandbox.id,
                client: daemonManager.canExposePorts ? client : nil
            )
        }
        .onReceive(NotificationCenter.default.publisher(for: .sandboxChanged)) { _ in
            refreshExposedPorts(vm, sandboxID: sandbox.id, client: client, daemonManager: daemonManager)
        }
        .errorToast(message: Bindable(vm).exposedPortsRefreshError)
    }
}

/// What the user typed into the expose form; `SandboxPortsExposeButton` sends
/// exactly these values.
@Observable
final class SandboxPortsForm {
    var sandboxPortText = ""
    var hostPortText = ""
    var networkProtocol = "tcp"
}

/// The expose form: sandbox port, host port, protocol, and the expose and
/// refresh buttons.
///
/// Reads only the form's fields. The two buttons are leaves of their own
/// because their enabled state follows the load state a refresh flips;
/// keeping that dependency out of this body is what keeps the segmented
/// picker out of every refresh.
struct SandboxPortsToolbar: View {
    let sandboxID: String
    @Bindable var form: SandboxPortsForm
    @Binding var isWorking: Bool

    var body: some View {
        HStack(spacing: 10) {
            TextField("Sandbox port", text: $form.sandboxPortText, prompt: Text("8080"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)

            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundStyle(AppColors.textSecondary)

            TextField("Host port", text: $form.hostPortText, prompt: Text("auto"))
                .textFieldStyle(.roundedBorder)
                .frame(width: 110)

            Picker("", selection: $form.networkProtocol) {
                Text("TCP").tag("tcp")
                Text("UDP").tag("udp")
            }
            .pickerStyle(.segmented)
            .frame(width: 110)

            Spacer()

            SandboxPortsExposeButton(sandboxID: sandboxID, form: form, isWorking: $isWorking)

            SandboxPortsRefreshButton(sandboxID: sandboxID, isWorking: $isWorking)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .recordingBodyEvaluation(of: Self.self)
    }
}

/// The Expose button; enabled once the form validates and the mappings of
/// `sandboxID` are loaded and idle.
struct SandboxPortsExposeButton: View {
    let sandboxID: String
    let form: SandboxPortsForm
    @Binding var isWorking: Bool

    @Environment(SandboxesViewModel.self) private var vm
    @Environment(DaemonManager.self) private var daemonManager
    @Environment(\.arcboxClient) private var client

    var body: some View {
        Button("Expose", action: expose)
            .disabled(!canExpose)
            .recordingBodyEvaluation(of: Self.self)
    }

    private var canExpose: Bool {
        guard
            vm.exposedPortsActionsAvailable(for: sandboxID, daemonManager: daemonManager, client: client),
            !isWorking
        else { return false }
        guard let port = UInt32(form.sandboxPortText), port > 0, port < 65536 else { return false }
        if !form.hostPortText.isEmpty {
            guard let host = UInt32(form.hostPortText), host > 0, host < 65536 else { return false }
        }
        return true
    }

    private func expose() {
        guard let port = UInt32(form.sandboxPortText) else { return }
        let hostPort = UInt32(form.hostPortText) ?? 0
        isWorking = true
        Task {
            _ = await vm.exposePort(
                sandboxID: sandboxID,
                sandboxPort: port,
                hostPort: hostPort,
                networkProtocol: form.networkProtocol,
                client: client
            )
            isWorking = false
        }
    }
}

/// The Refresh button; enabled while the daemon can answer and no load is in flight.
struct SandboxPortsRefreshButton: View {
    let sandboxID: String
    @Binding var isWorking: Bool

    @Environment(SandboxesViewModel.self) private var vm
    @Environment(DaemonManager.self) private var daemonManager
    @Environment(\.arcboxClient) private var client

    var body: some View {
        Button {
            refreshExposedPorts(vm, sandboxID: sandboxID, client: client, daemonManager: daemonManager)
        } label: {
            Label("Refresh port mappings", systemImage: "arrow.clockwise")
                .labelStyle(.iconOnly)
                .font(.system(size: 12))
        }
        .buttonStyle(.plain)
        .disabled(!vm.canRefreshExposedPorts(daemonManager: daemonManager, client: client) || isWorking)
        .help("Refresh")
        .recordingBodyEvaluation(of: Self.self)
    }
}

/// The mapping list, or the placeholder for the load state it is in.
struct SandboxPortsContent: View {
    let sandboxID: String
    @Binding var isWorking: Bool

    @Environment(SandboxesViewModel.self) private var vm
    @Environment(DaemonManager.self) private var daemonManager
    @Environment(\.arcboxClient) private var client

    private var mappings: [SandboxExposedPort] {
        vm.exposedPorts[sandboxID] ?? []
    }

    var body: some View {
        content
            .recordingBodyEvaluation(of: Self.self)
    }

    @ViewBuilder
    private var content: some View {
        if vm.exposedPortsSandboxID != sandboxID {
            loadingPlaceholder("Preparing port mappings…")
        } else {
            switch vm.exposedPortsLoadState {
            case .waiting:
                loadingPlaceholder("Waiting for ArcBox daemon…")
            case .loading:
                loadingPlaceholder("Loading port mappings…")
            case .failed(let message):
                ContentUnavailableView {
                    Label("Couldn’t Load Port Mappings", systemImage: "exclamationmark.triangle")
                } description: {
                    Text(message)
                } actions: {
                    Button("Retry") {
                        refreshExposedPorts(
                            vm, sandboxID: sandboxID, client: client, daemonManager: daemonManager)
                    }
                    .disabled(!vm.canRefreshExposedPorts(daemonManager: daemonManager, client: client) || isWorking)
                }
            case .loaded:
                loadedContent
            }
        }
    }

    @ViewBuilder
    private var loadedContent: some View {
        if mappings.isEmpty {
            VStack(spacing: 10) {
                Spacer()
                Image(systemName: "network")
                    .font(.system(size: 24))
                    .foregroundStyle(AppColors.textMuted)
                Text("No exposed ports.")
                    .font(.system(size: 13))
                    .foregroundStyle(AppColors.textSecondary)
                Text("Expose one above, or use the CLI or SDK and refresh.")
                    .font(.system(size: 12))
                    .foregroundStyle(AppColors.textMuted)
                    .multilineTextAlignment(.center)
                    .padding(.horizontal, 24)
                Spacer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(spacing: 0) {
                    ForEach(mappings) { mapping in
                        mappingRow(mapping)
                        Divider()
                    }
                }
            }
        }
    }

    private func loadingPlaceholder(_ message: String) -> some View {
        VStack(spacing: 12) {
            Spacer()
            ProgressView()
                .controlSize(.small)
            Text(message)
                .font(.system(size: 13))
                .foregroundStyle(AppColors.textSecondary)
            Spacer()
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func mappingRow(_ mapping: SandboxExposedPort) -> some View {
        HStack(spacing: 10) {
            Text("\(mapping.networkProtocol.uppercased()) \(mapping.sandboxPort)")
                .font(.system(size: 12, design: .monospaced))

            Image(systemName: "arrow.right")
                .font(.system(size: 10))
                .foregroundStyle(AppColors.textSecondary)

            if mapping.networkProtocol == "tcp", let url = mapping.localURL {
                Link("localhost:\(mapping.hostPort)", destination: url)
                    .font(.system(size: 12, design: .monospaced))
                    .help("Open in browser")
            } else {
                Text("localhost:\(mapping.hostPort)")
                    .font(.system(size: 12, design: .monospaced))
            }

            Spacer()

            Button {
                unexpose(mapping)
            } label: {
                Image(systemName: "xmark.circle")
                    .foregroundStyle(AppColors.textSecondary)
            }
            .buttonStyle(.plain)
            .disabled(
                !vm.exposedPortsActionsAvailable(for: sandboxID, daemonManager: daemonManager, client: client)
                    || isWorking
            )
            .help("Remove mapping")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
    }

    private func unexpose(_ mapping: SandboxExposedPort) {
        isWorking = true
        Task {
            await vm.unexposePort(
                sandboxID: sandboxID,
                sandboxPort: mapping.sandboxPort,
                networkProtocol: mapping.networkProtocol,
                client: client
            )
            isWorking = false
        }
    }
}

/// Reloads the mappings of `sandboxID` when, at the moment the task runs, it
/// is still the selected sandbox and the daemon can still answer.
private func refreshExposedPorts(
    _ vm: SandboxesViewModel,
    sandboxID: String,
    client: ArcBoxClient?,
    daemonManager: DaemonManager
) {
    Task {
        guard
            !Task.isCancelled,
            vm.selectedID == sandboxID,
            daemonManager.canExposePorts,
            client != nil
        else { return }
        await vm.loadExposedPorts(for: sandboxID, client: client)
    }
}

extension SandboxesViewModel {
    /// Expose and unexpose are available once the mappings of `sandboxID`
    /// are loaded and no load is in flight.
    ///
    /// The view model's flags come first in both conjunctions so a body that
    /// evaluates them observes the same properties whether or not the daemon
    /// is ready; `&&` would otherwise stop reading at a stopped daemon.
    fileprivate func exposedPortsActionsAvailable(
        for sandboxID: String,
        daemonManager: DaemonManager,
        client: ArcBoxClient?
    ) -> Bool {
        exposedPortsSandboxID == sandboxID
            && exposedPortsLoadState == .loaded
            && !isLoadingExposedPorts
            && daemonManager.canExposePorts
            && client != nil
    }

    fileprivate func canRefreshExposedPorts(daemonManager: DaemonManager, client: ArcBoxClient?) -> Bool {
        !isLoadingExposedPorts && daemonManager.canExposePorts && client != nil
    }
}

extension DaemonManager {
    /// The daemon is up and its Docker API answers, which port exposure needs.
    fileprivate var canExposePorts: Bool {
        state.isRunning && setupPhase.isDockerReady
    }
}

private struct PortLoadID: Equatable {
    let sandboxID: String
    let client: ObjectIdentifier?
    let runtimeReady: Bool
}
