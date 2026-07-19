import ArcBoxClient
import Foundation
import OSLog

/// Parameters for creating a machine.
struct MachineCreateSpec {
    var name = ""
    var distro = ""
    var version = ""
    var cpus: UInt32 = 0
    var memoryGiB: UInt64 = 4
    var diskGiB: UInt64 = 50
}

extension MachinesViewModel {
    // MARK: - gRPC Lifecycle Operations

    /// Load machines from the daemon via gRPC List.
    ///
    /// The `default` machine is the System VM hosting Docker/Kubernetes; its
    /// lifecycle belongs to the app, not this tab, so it is hidden here.
    func loadMachines(client: ArcBoxClient?) async {
        guard let client else {
            loadState = .waiting
            return
        }
        if loadState == .waiting {
            loadState = .loading
        }
        let transitioning = transitioningIDs
        let existingByID = Dictionary(uniqueKeysWithValues: machines.map { ($0.id, $0) })
        var request = Arcbox_V1_ListMachinesRequest()
        request.all = true
        do {
            let response = try await client.machines.list(
                request,
                options: ArcBoxClient.defaultCallOptions
            )
            var viewModels = response.machines
                .filter { $0.id != "default" }
                .map { summary -> MachineViewModel in
                    var vm = MachineViewModel(from: summary)
                    // Preserve Inspect-only fields so a list refresh does not
                    // wipe data the summary endpoint doesn't return.
                    if let existing = existingByID[vm.id] {
                        vm.preserveDetailFrom(existing)
                    }
                    return vm
                }
                .sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
            for i in viewModels.indices where transitioning.contains(viewModels[i].id) {
                viewModels[i].isTransitioning = true
            }
            machines = viewModels
            loadState = .loaded
        } catch {
            let message = reportError(error, operation: "list", surface: false)
            loadState = .failed(message)
        }
    }

    /// Load Inspect-only details of one machine (arch, network, mounts).
    func loadMachineDetails(_ id: String, client: ArcBoxClient?) async {
        guard let client else { return }
        var request = Arcbox_V1_InspectMachineRequest()
        request.id = id
        do {
            let info = try await client.machines.inspect(
                request,
                options: ArcBoxClient.defaultCallOptions
            )
            updateMachine(id) { machine in
                machine.applyDetails(from: info)
            }
        } catch {
            reportError(error, operation: "inspect", surface: false)
        }
    }

    /// Create a machine from a published distro image and start it.
    /// Returns the new machine ID on success.
    @discardableResult
    func createMachine(_ spec: MachineCreateSpec, client: ArcBoxClient?) async -> String? {
        guard let client else { return nil }
        var request = Arcbox_V1_CreateMachineRequest()
        request.name = spec.name
        request.distro = spec.distro
        request.version = spec.version
        request.cpus = spec.cpus
        request.memory = spec.memoryGiB << 30
        request.diskSize = spec.diskGiB << 30
        do {
            // Create pulls the distro image from the CDN on first use.
            let response = try await client.machines.create(
                request,
                options: ArcBoxClient.machineCreateCallOptions
            )
            Log.machine.info("Created machine \(response.id, privacy: .public)")
            await loadMachines(client: client)
            await startMachine(response.id, client: client)
            return response.id
        } catch {
            reportError(error, operation: "create")
            return nil
        }
    }

    func startMachine(_ id: String, client: ArcBoxClient?) async {
        lastError = nil
        guard let client else { return }
        setTransitioning(id, true)
        var request = Arcbox_V1_StartMachineRequest()
        request.id = id
        do {
            _ = try await client.machines.start(
                request,
                options: ArcBoxClient.systemVmRestartCallOptions
            )
        } catch {
            // Starting an already-running machine is a no-op, not a failure.
            if !ArcBoxClient.rpcMessage(error, contains: "already running") {
                reportError(error, operation: "start")
            }
        }
        setTransitioning(id, false)
        await loadMachines(client: client)
    }

    func stopMachine(_ id: String, client: ArcBoxClient?) async {
        lastError = nil
        guard let client else { return }
        setTransitioning(id, true)
        var request = Arcbox_V1_StopMachineRequest()
        request.id = id
        do {
            _ = try await client.machines.stop(
                request,
                options: ArcBoxClient.systemVmRestartCallOptions
            )
        } catch {
            // Stopping a machine that is not running is a no-op, not a failure.
            if !ArcBoxClient.rpcMessage(error, contains: "not running") {
                reportError(error, operation: "stop")
            }
        }
        setTransitioning(id, false)
        await loadMachines(client: client)
    }

    func deleteMachine(_ id: String, client: ArcBoxClient?) async {
        lastError = nil
        guard let client else { return }
        setTransitioning(id, true)
        var request = Arcbox_V1_RemoveMachineRequest()
        request.id = id
        request.force = true
        do {
            _ = try await client.machines.remove(
                request,
                options: ArcBoxClient.systemVmRestartCallOptions
            )
            if selectedID == id {
                selectedID = nil
            }
        } catch {
            reportError(error, operation: "remove")
        }
        setTransitioning(id, false)
        await loadMachines(client: client)
    }
}
