import DockerClient
import Foundation
import os

extension ContainersViewModel {
    // MARK: - Batch Docker Operations

    func startContainersDocker(_ ids: [String], docker: DockerClient?) async {
        guard let docker else { return }
        let stoppedIDs = ids.filter { id in
            containers.first(where: { $0.id == id })?.isRunning == false
        }
        for id in stoppedIDs { setTransitioning(id, true) }
        await withTaskGroup(of: Void.self) { group in
            for id in stoppedIDs {
                group.addTask { [weak self] in
                    do {
                        _ = try await docker.api.ContainerStart(path: .init(id: id))
                        await self?.setContainerRunningState(id, isRunning: true)
                    } catch {
                        Log.container.error(
                            "Error starting container \(id, privacy: .private): \(error.localizedDescription, privacy: .private)"
                        )
                        ErrorReporting.capture(error, domain: .container, operation: "batch_start")
                    }
                }
            }
        }
        for id in stoppedIDs { setTransitioning(id, false) }
        await loadContainersFromDocker(docker: docker)
    }

    func stopContainersDocker(_ ids: [String], docker: DockerClient?) async {
        guard let docker else { return }
        let runningIDs = ids.filter { id in
            containers.first(where: { $0.id == id })?.isRunning == true
        }
        for id in runningIDs { setTransitioning(id, true) }
        await withTaskGroup(of: Void.self) { group in
            for id in runningIDs {
                group.addTask { [weak self] in
                    do {
                        _ = try await docker.api.ContainerStop(path: .init(id: id))
                        await self?.setContainerRunningState(id, isRunning: false)
                    } catch {
                        Log.container.error(
                            "Error stopping container \(id, privacy: .private): \(error.localizedDescription, privacy: .private)"
                        )
                        ErrorReporting.capture(error, domain: .container, operation: "batch_stop")
                    }
                }
            }
        }
        for id in runningIDs { setTransitioning(id, false) }
        await loadContainersFromDocker(docker: docker)
    }

    func removeContainersDocker(_ ids: [String], docker: DockerClient?) async {
        guard let docker else { return }
        for id in ids { setTransitioning(id, true) }
        await withTaskGroup(of: Void.self) { group in
            for id in ids {
                group.addTask { [weak self] in
                    do {
                        _ = try await docker.api.ContainerDelete(path: .init(id: id), query: .init(force: true))
                        await self?.removeContainerLocally(id)
                    } catch {
                        Log.container.error(
                            "Error removing container \(id, privacy: .private): \(error.localizedDescription, privacy: .private)"
                        )
                        ErrorReporting.capture(error, domain: .container, operation: "batch_remove")
                    }
                }
            }
        }
        NotificationCenter.default.post(name: .dockerDataChanged, object: nil)
        await loadContainersFromDocker(docker: docker)
    }

}
