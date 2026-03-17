import Foundation

@MainActor
final class ContainerRouteController {
    typealias RouteOperation = @MainActor (_ subnet: String, _ iface: String) async throws -> Void
    typealias BridgeProvider = @MainActor () async -> String?
    typealias Sleeper = (Duration) async -> Void

    static let containerSubnet = "172.16.0.0/12"
    static let maxRouteRetries = 10
    static let retryInterval: Duration = .seconds(2)

    private let addRouteInterface: RouteOperation
    private let removeRouteInterface: RouteOperation
    private let bridgeProvider: BridgeProvider
    private let sleeper: Sleeper

    private(set) var installedRouteInterface: String?

    init(
        addRouteInterface: @escaping RouteOperation,
        removeRouteInterface: @escaping RouteOperation,
        bridgeProvider: @escaping BridgeProvider = {
            let bridgeMACAddress = await MachineBridgeIdentity.fetchDefaultMachineBridgeMAC()
            return VmnetBridgeDiscovery.findBridgeInterface(targetMACAddress: bridgeMACAddress)
        },
        sleeper: @escaping Sleeper = { duration in try? await Task.sleep(for: duration) }
    ) {
        self.addRouteInterface = addRouteInterface
        self.removeRouteInterface = removeRouteInterface
        self.bridgeProvider = bridgeProvider
        self.sleeper = sleeper
    }

    func installRoutes() async {
        for attempt in 1...Self.maxRouteRetries {
            guard let bridgeIface = await bridgeProvider() else {
                ClientLog.helper.debug(
                    "Route attempt \(attempt)/\(Self.maxRouteRetries): bridge interface not found, retrying"
                )
                if attempt < Self.maxRouteRetries {
                    await sleeper(Self.retryInterval)
                }
                continue
            }

            do {
                try await addRouteInterface(Self.containerSubnet, bridgeIface)
                installedRouteInterface = bridgeIface
                ClientLog.helper.info(
                    "Route installed: \(Self.containerSubnet) -interface \(bridgeIface, privacy: .public) (attempt \(attempt))"
                )
                return
            } catch {
                ClientLog.helper.warning(
                    "Route attempt \(attempt) failed: \(error.localizedDescription, privacy: .public)"
                )
                if attempt < Self.maxRouteRetries {
                    await sleeper(Self.retryInterval)
                }
            }
        }

        ClientLog.helper.error(
            "Failed to install container route after \(Self.maxRouteRetries) attempts"
        )
    }

    func removeRoutes() async {
        guard let iface = installedRouteInterface else { return }
        do {
            try await removeRouteInterface(Self.containerSubnet, iface)
            ClientLog.helper.info(
                "Route removed: \(Self.containerSubnet) -interface \(iface, privacy: .public)"
            )
        } catch {
            ClientLog.helper.warning(
                "Route cleanup failed: \(error.localizedDescription, privacy: .public)"
            )
        }
        installedRouteInterface = nil
    }
}
