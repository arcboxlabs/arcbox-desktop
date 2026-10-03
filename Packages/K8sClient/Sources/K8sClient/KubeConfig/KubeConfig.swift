import Foundation

/// Parsed kubeconfig credentials for connecting to a Kubernetes API server.
@available(macOS 15.0, *)
public struct KubeConfig: Sendable {
    /// How the client authenticates to the API server.
    public enum AuthMode: Sendable {
        case certificate
        case bearerToken(String)
        /// The selected user names an exec credential plugin that has not run yet.
        /// `resolvingCredentials()` runs it; `K8sClient` refuses a config in this state.
        case execPlugin
    }

    /// API server URL (e.g. "https://127.0.0.1:16443").
    public let server: String
    /// Base64-decoded certificate authority data from kubeconfig (PEM or DER).
    public let certificateAuthorityData: Data
    /// Base64-decoded client certificate data from kubeconfig (PEM or DER).
    /// Only present for certificate auth mode.
    public let clientCertificateData: Data?
    /// Base64-decoded client private key data from kubeconfig (PEM or DER).
    /// Only present for certificate auth mode.
    public let clientKeyData: Data?
    /// Authentication mode detected from the kubeconfig.
    public let authMode: AuthMode
    /// The plugin behind `.execPlugin`; `nil` in the other modes.
    let execPlugin: ExecConfig?

    /// Parse a kubeconfig YAML string into credentials. Nothing runs: a user with an `exec`
    /// plugin parses to `.execPlugin`, and `resolvingCredentials()` runs the plugin.
    ///
    /// Supports two authentication modes:
    /// - **Certificate auth**: `client-certificate-data` + `client-key-data` (mTLS)
    /// - **Exec credential plugin**: an external command that prints a bearer token
    ///
    /// If both are present, certificate auth takes precedence.
    public init(yaml: String) throws {
        let document = try Self.parseKubeConfigDocument(from: yaml)
        let context = document.currentContext.flatMap { currentContext in
            document.contexts?.first { $0.name == currentContext }?.context
        }

        let cluster: NamedCluster?
        if let context {
            cluster = document.clusters.first { $0.name == context.cluster }
            guard cluster != nil else {
                throw KubeConfigError.missingField("cluster \(context.cluster)")
            }
        } else {
            cluster = document.clusters.first
        }

        guard let cluster else {
            throw KubeConfigError.missingField("server")
        }
        guard let server = cluster.cluster.server else {
            throw KubeConfigError.missingField("server")
        }
        guard let caB64 = cluster.cluster.certificateAuthorityData,
            let caData = Data(base64Encoded: caB64)
        else {
            throw KubeConfigError.missingField("certificate-authority-data")
        }

        let user: NamedUser?
        if let context {
            user = document.users.first { $0.name == context.user }
            guard user != nil else {
                throw KubeConfigError.missingField("user \(context.user)")
            }
        } else {
            user = document.users.first
        }

        // Try certificate auth first
        let certB64 = user?.user.clientCertificateData
        let keyB64 = user?.user.clientKeyData

        if let certB64, let keyB64,
            let certData = Data(base64Encoded: certB64),
            let keyData = Data(base64Encoded: keyB64)
        {
            self.init(
                server: server,
                certificateAuthorityData: caData,
                clientCertificateData: certData,
                clientKeyData: keyData,
                authMode: .certificate,
                execPlugin: nil
            )
            return
        }

        // Fall back to exec credential plugin
        if let exec = user?.user.exec {
            self.init(
                server: server,
                certificateAuthorityData: caData,
                clientCertificateData: nil,
                clientKeyData: nil,
                authMode: .execPlugin,
                execPlugin: exec
            )
            return
        }

        throw KubeConfigError.missingField("client-certificate-data or exec")
    }

    private init(
        server: String,
        certificateAuthorityData: Data,
        clientCertificateData: Data?,
        clientKeyData: Data?,
        authMode: AuthMode,
        execPlugin: ExecConfig?
    ) {
        self.server = server
        self.certificateAuthorityData = certificateAuthorityData
        self.clientCertificateData = clientCertificateData
        self.clientKeyData = clientKeyData
        self.authMode = authMode
        self.execPlugin = execPlugin
    }

    /// Parses `yaml` and runs its exec credential plugin when the selected user has one.
    public static func load(yaml: String, execTimeout: Duration = .seconds(15)) async throws -> KubeConfig {
        try await KubeConfig(yaml: yaml).resolvingCredentials(timeout: execTimeout)
    }

    /// Runs the exec credential plugin and returns a config carrying the bearer token it
    /// printed. A config without a plugin comes back unchanged.
    ///
    /// The plugin (`aws eks get-token`, `gke-gcloud-auth-plugin`, ...) can take seconds; it is
    /// awaited off the calling actor and terminated after `timeout`.
    public func resolvingCredentials(timeout: Duration = .seconds(15)) async throws -> KubeConfig {
        guard let execPlugin else { return self }
        let token = try await Self.runExecPlugin(
            command: execPlugin.command,
            args: execPlugin.args,
            env: execPlugin.env,
            timeout: timeout
        )
        return KubeConfig(
            server: server,
            certificateAuthorityData: certificateAuthorityData,
            clientCertificateData: nil,
            clientKeyData: nil,
            authMode: .bearerToken(token),
            execPlugin: nil
        )
    }

    /// Create a URLSession configured with appropriate auth from this kubeconfig.
    ///
    /// - Parameter streaming: relaxes the timeouts for long-lived watch connections. The
    ///   resource timeout would otherwise tear a healthy watch down after 60s. The idle
    ///   timeout still applies, so a silent connection reconnects instead of hanging.
    public func makeURLSession(streaming: Bool = false) throws -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = streaming ? 300 : 15
        config.timeoutIntervalForResource = streaming ? 86400 : 60

        let delegate = try KubeTLSDelegate(config: self)
        return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
    }
}
