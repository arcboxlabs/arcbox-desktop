import Foundation

// Protocol version. Bump when the API surface changes to prevent stale helpers
// from being called with incompatible arguments.
let kArcBoxHelperProtocolVersion = 1

@objc protocol ArcBoxHelperProtocol {

    // MARK: - Operation 1: /var/run/docker.sock

    /// Creates symlink: /var/run/docker.sock -> socketPath.
    ///
    /// Safety rules enforced by the helper:
    /// - socketPath must match /Users/<name>/.arcbox/*.sock (regex, not FileManager.home)
    /// - If /var/run/docker.sock already points to socketPath: no-op (idempotent)
    /// - If /var/run/docker.sock points to another ArcBox path: replace
    /// - If /var/run/docker.sock points to a non-ArcBox path (live OR dead): return error, do not replace
    /// - If /var/run/docker.sock is a regular file: return error, do not remove
    func setupDockerSocket(socketPath: String, reply: @escaping (NSError?) -> Void)

    /// Removes /var/run/docker.sock only if it points to an ArcBox socket path.
    /// No-op if the symlink points elsewhere (e.g., Docker Desktop).
    func teardownDockerSocket(reply: @escaping (NSError?) -> Void)

    // MARK: - Operation 2: CLI tools in /usr/local/bin

    /// Creates symlink: /usr/local/bin/abctl -> <appBundlePath>/Contents/MacOS/bin/abctl
    ///
    /// appBundlePath must be under /Applications/ (validated by helper).
    /// Only removes an existing link if it already points into an ArcBox bundle.
    func installCLITools(appBundlePath: String, reply: @escaping (NSError?) -> Void)

    /// Removes /usr/local/bin/abctl only if it points into an ArcBox.app bundle.
    func uninstallCLITools(reply: @escaping (NSError?) -> Void)

    // MARK: - Operation 3: /etc/resolver

    /// Writes /etc/resolver/<domain> with nameserver 127.0.0.1 at the given port.
    /// domain must be in the allowed list (validated by helper).
    func setupDNSResolver(domain: String, port: Int, reply: @escaping (NSError?) -> Void)

    /// Removes /etc/resolver/<domain>.
    func teardownDNSResolver(domain: String, reply: @escaping (NSError?) -> Void)

    // MARK: - Operation 4: Network routes

    /// Installs a host route via gateway: /sbin/route -n add -net <subnet> <gateway>.
    func addRouteGateway(subnet: String, gateway: String, reply: @escaping (NSError?) -> Void)

    /// Installs a host route via interface: /sbin/route -n add -net <subnet> -interface <iface>.
    /// Used for L3 direct routing with proxy ARP.
    func addRouteInterface(subnet: String, iface: String, reply: @escaping (NSError?) -> Void)

    /// Removes a gateway host route.
    func removeRouteGateway(subnet: String, gateway: String, reply: @escaping (NSError?) -> Void)

    /// Removes an interface host route: /sbin/route -n delete -net <subnet> -interface <iface>.
    func removeRouteInterface(subnet: String, iface: String, reply: @escaping (NSError?) -> Void)

    // MARK: - Lifecycle

    /// Returns the helper protocol version for compatibility checking.
    func getVersion(reply: @escaping (Int) -> Void)
}
