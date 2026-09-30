import DockerClient
import SwiftUI

/// Logs tab showing real container log output with streaming support.
///
/// The tab itself reads no streaming state: `ContainerLogsToolbar` and
/// `ContainerLogsContent` each observe only what they render, so a batch of
/// lines re-evaluates the content alone (`ContainerLogsModel`).
struct ContainerLogsTab: View {
    let container: ContainerViewModel

    @Environment(\.dockerClient) private var docker

    @State private var model: ContainerLogsModel

    /// `model` is the seam the relayout regression tests drive log batches through.
    init(container: ContainerViewModel, model: ContainerLogsModel = ContainerLogsModel()) {
        self.container = container
        _model = State(initialValue: model)
    }

    var body: some View {
        VStack(spacing: 0) {
            ContainerLogsToolbar(model: model)
            Divider()
            ContainerLogsContent(model: model)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(AppColors.background)
        .task(id: container.id) {
            await model.startStreaming(containerID: container.id, docker: docker)
        }
        .onDisappear {
            model.cancelStreaming()
        }
    }
}
