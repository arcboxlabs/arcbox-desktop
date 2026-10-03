import DockerClient
import Foundation
import os

extension ContainersViewModel {
    // MARK: - Batch Docker Operations

    func startContainersDocker(_ ids: [String], docker: DockerClient?) async {
        lastError = nil
        guard let docker else {
            lastError = "Docker client unavailable."
            return
        }
        let stoppedIDs = ids.filter { id in
            containers.first(where: { $0.id == id })?.isRunning == false
        }
        for id in stoppedIDs { setTransitioning(id, true) }
        let errors = await batch(stoppedIDs) { id in
            do {
                let response = try await docker.api.ContainerStart(path: .init(id: id))
                if let message = response.startFailureMessage {
                    return message
                }
                await self.setContainerRunningState(id, isRunning: true)
                Analytics.capture(.containerStarted, properties: ["backend": "docker", "batch": true])
                return nil
            } catch {
                Log.container.error(
                    "Error starting container \(id, privacy: .private): \(error.localizedDescription, privacy: .private)"
                )
                ErrorReporting.capture(error, domain: .container, operation: "batch_start")
                return error.localizedDescription
            }
        }
        for id in stoppedIDs { setTransitioning(id, false) }
        surfaceBatchErrors(errors, action: "start")
        await loadContainersFromDocker(docker: docker)
    }

    func stopContainersDocker(_ ids: [String], docker: DockerClient?) async {
        lastError = nil
        guard let docker else {
            lastError = "Docker client unavailable."
            return
        }
        let runningIDs = ids.filter { id in
            containers.first(where: { $0.id == id })?.isRunning == true
        }
        for id in runningIDs { setTransitioning(id, true) }
        let errors = await batch(runningIDs) { id in
            do {
                let response = try await docker.api.ContainerStop(path: .init(id: id))
                if let message = response.stopFailureMessage {
                    return message
                }
                await self.setContainerRunningState(id, isRunning: false)
                Analytics.capture(.containerStopped, properties: ["backend": "docker", "batch": true])
                return nil
            } catch {
                Log.container.error(
                    "Error stopping container \(id, privacy: .private): \(error.localizedDescription, privacy: .private)"
                )
                ErrorReporting.capture(error, domain: .container, operation: "batch_stop")
                return error.localizedDescription
            }
        }
        for id in runningIDs { setTransitioning(id, false) }
        surfaceBatchErrors(errors, action: "stop")
        await loadContainersFromDocker(docker: docker)
    }

    func removeContainersDocker(_ ids: [String], docker: DockerClient?) async {
        lastError = nil
        guard let docker else {
            lastError = "Docker client unavailable."
            return
        }
        for id in ids { setTransitioning(id, true) }
        let errors = await batch(ids) { id in
            do {
                let response = try await docker.api.ContainerDelete(
                    path: .init(id: id),
                    query: .init(force: true)
                )
                if let message = response.deleteFailureMessage {
                    return message
                }
                await self.removeContainerLocally(id)
                Analytics.capture(.containerRemoved, properties: ["backend": "docker", "batch": true])
                return nil
            } catch {
                Log.container.error(
                    "Error removing container \(id, privacy: .private): \(error.localizedDescription, privacy: .private)"
                )
                ErrorReporting.capture(error, domain: .container, operation: "batch_remove")
                return error.localizedDescription
            }
        }
        for id in ids { setTransitioning(id, false) }
        surfaceBatchErrors(errors, action: "remove")
        NotificationCenter.default.post(name: .dockerDataChanged, object: nil)
        await loadContainersFromDocker(docker: docker)
    }

    /// Runs `operation` over `ids`, at most ``batchConcurrency`` of them at a time, and
    /// collects whatever came back as a failure message.
    func batch(
        _ ids: [String],
        _ operation: @escaping @Sendable (String) async -> String?
    ) async -> [String] {
        await withTaskGroup(of: String?.self, returning: [String].self) { group in
            var errors: [String] = []
            var next = ids.startIndex
            func addTask() {
                guard next < ids.endIndex else { return }
                let id = ids[next]
                next = ids.index(after: next)
                group.addTask { await operation(id) }
            }
            for _ in 0..<min(Self.batchConcurrency, ids.count) { addTask() }
            while let error = await group.next() {
                if let error { errors.append(error) }
                addTask()
            }
            return errors
        }
    }

    /// Docker holds a stop open for its full stop timeout, so selecting fifty containers
    /// used to put fifty requests in flight at once and starve the client's connection
    /// pool — the next list refresh then failed with `getConnectionFromPoolTimeout`.
    static let batchConcurrency = 6

    private func surfaceBatchErrors(_ errors: [String], action: String) {
        guard let first = errors.first else { return }
        lastError =
            errors.count == 1
            ? first
            : "\(errors.count) containers failed to \(action). \(first)"
    }
}
