import Foundation

/// Errors from kubeconfig parsing and credential resolution.
public enum KubeConfigError: Error, Sendable {
    case missingField(String)
    case invalidCertificate(String)
    case execPluginFailed(String)
    /// `K8sClient` was given a config whose exec plugin has not run. Resolve it first with
    /// `KubeConfig.load(yaml:)` or `resolvingCredentials()`.
    case unresolvedExecPlugin
}
