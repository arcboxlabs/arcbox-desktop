import Foundation

/// Parsed kubeconfig credentials for connecting to a Kubernetes API server.
@available(macOS 15.0, *)
public struct KubeConfig: Sendable {
    /// How the client authenticates to the API server.
    public enum AuthMode: Sendable {
        case certificate
        case bearerToken(String)
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

    /// Parse a kubeconfig YAML string into credentials.
    ///
    /// Supports two authentication modes:
    /// - **Certificate auth**: `client-certificate-data` + `client-key-data` (mTLS)
    /// - **Exec credential plugin**: runs an external command to obtain a bearer token
    ///
    /// If both are present, certificate auth takes precedence.
    public init(yaml: String) throws {
        let document = try Self.parseKubeConfigDocument(from: yaml)
        let context = document.currentContext.flatMap { currentContext in
            document.contexts?.first { $0.name == currentContext }?.context
        }

        let cluster: KubeConfig.NamedCluster?
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

        self.server = server
        self.certificateAuthorityData = caData

        let user: KubeConfig.NamedUser?
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
            self.clientCertificateData = certData
            self.clientKeyData = keyData
            self.authMode = .certificate
            return
        }

        // Fall back to exec credential plugin
        let exec = user?.user.exec
        if let exec {
            let token = try Self.runExecPlugin(
                command: exec.command,
                args: exec.args,
                env: exec.env
            )
            self.clientCertificateData = nil
            self.clientKeyData = nil
            self.authMode = .bearerToken(token)
            return
        }

        throw KubeConfigError.missingField("client-certificate-data or exec")
    }

    /// Create a URLSession configured with appropriate auth from this kubeconfig.
    public func makeURLSession() throws -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.timeoutIntervalForRequest = 15
        config.timeoutIntervalForResource = 60

        switch authMode {
        case .certificate:
            let delegate = try KubeTLSDelegate(config: self)
            return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        case .bearerToken:
            let delegate = try KubeBearerTokenDelegate(caData: certificateAuthorityData)
            return URLSession(configuration: config, delegate: delegate, delegateQueue: nil)
        }
    }
}
