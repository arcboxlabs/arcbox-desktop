import ArcBoxClient
import DockerClient
import SwiftUI

private struct ArcBoxClientKey: EnvironmentKey {
    static let defaultValue: ArcBoxClient? = nil
}

private struct DockerClientKey: EnvironmentKey {
    static let defaultValue: DockerClient? = nil
}

private struct StartupOrchestratorKey: EnvironmentKey {
    static let defaultValue: StartupOrchestrator? = nil
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

    var startupOrchestrator: StartupOrchestrator? {
        get { self[StartupOrchestratorKey.self] }
        set { self[StartupOrchestratorKey.self] = newValue }
    }
}
