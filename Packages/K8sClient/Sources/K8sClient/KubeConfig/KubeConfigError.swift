import Foundation

/// Errors from kubeconfig parsing.
public enum KubeConfigError: Error, Sendable {
    case missingField(String)
    case invalidCertificate(String)
    case execPluginFailed(String)
}
