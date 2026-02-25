import SwiftUI
import ArcBoxClient
import DockerClient

@main
struct ArcBoxDesktopApp: App {
    @State private var appVM = AppViewModel()
    @State private var daemonManager = DaemonManager()
    @State private var arcboxClient: ArcBoxClient?
    @State private var dockerClient: DockerClient? = DockerClient()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(appVM)
                .environment(daemonManager)
                .environment(\.arcboxClient, arcboxClient)
                .environment(\.dockerClient, dockerClient)
                .frame(minWidth: 900, minHeight: 600)
                .task {
                    // Initialize ArcBox daemon client
                    await daemonManager.startDaemon()
                    if daemonManager.state.isRunning {
                        do {
                            let client = try ArcBoxClient()
                            Task { try await client.runConnections() }
                            arcboxClient = client
                        } catch {}
                    }
                }
        }
        .defaultSize(width: 1200, height: 800)
    }
}

// MARK: - Environment Keys

private struct ArcBoxClientKey: EnvironmentKey {
    static let defaultValue: ArcBoxClient? = nil
}

private struct DockerClientKey: EnvironmentKey {
    static let defaultValue: DockerClient? = nil
}

extension EnvironmentValues {
    var arcboxClient: ArcBoxClient? {
        get { self[ArcBoxClientKey.self] }
        set { self[ArcBoxClientKey.self] = newValue }
    }

    var dockerClient: DockerClient? {
        get { self[DockerClientKey.self] }
        set { self[DockerClientKey.self] = newValue }
    }
}
