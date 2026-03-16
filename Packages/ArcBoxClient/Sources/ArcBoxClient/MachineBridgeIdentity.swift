import Foundation

enum MachineBridgeIdentity {
    private static let defaultMachineID = "default"

    static func fetchDefaultMachineBridgeMAC(
        socketPath: String = ArcBoxClient.defaultSocketPath
    ) async -> String? {
        do {
            let client = try ArcBoxClient(socketPath: socketPath)
            let connections = Task {
                try? await client.runConnections()
            }
            defer {
                client.close()
                connections.cancel()
            }

            var request = Arcbox_V1_InspectMachineRequest()
            request.id = defaultMachineID
            let machine = try await client.machines.inspect(request)
            let macAddress = machine.network.bridgeMacAddress
                .trimmingCharacters(in: .whitespacesAndNewlines)

            guard !macAddress.isEmpty else {
                return nil
            }

            return VmnetBridgeDiscovery.normalizeMACAddress(macAddress)
        } catch {
            ClientLog.helper.debug(
                "Failed to fetch default machine bridge MAC: \(error.localizedDescription, privacy: .public)"
            )
            return nil
        }
    }
}
