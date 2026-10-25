import Foundation

/// Provider-level auth operations, abstracted so `AuthSession` can be tested
/// against a fake provider.
public protocol AuthProviding: Sendable {
    /// Starts a device authorization (RFC 8628 §3.1).
    func requestDeviceCode(
        configuration: AuthClientConfiguration
    ) async throws -> DeviceCodeGrant

    /// One poll of the token endpoint. Terminal denial/expiry throw.
    func pollDeviceToken(
        deviceCode: String,
        configuration: AuthClientConfiguration
    ) async throws -> DevicePollOutcome

    /// Validates the session token and returns the provider's view of it,
    /// or `nil` when the provider authoritatively reports no session.
    /// Transport and server failures throw instead, so callers never treat
    /// an outage as a sign-out.
    func session(
        token: String,
        configuration: AuthClientConfiguration
    ) async throws -> SessionSnapshot?

    /// Revokes the session server-side.
    func signOut(
        token: String,
        configuration: AuthClientConfiguration
    ) async throws
}
