import Foundation

/// A pending device authorization issued by the provider (RFC 8628 §3.2).
public struct DeviceCodeGrant: Sendable, Equatable, Decodable {
    /// Opaque code the app polls the token endpoint with. Never shown.
    public let deviceCode: String
    /// Short code the user confirms in the browser.
    public let userCode: String
    public let verificationURI: URL
    /// Verification URL with the user code pre-filled, when provided.
    public let verificationURIComplete: URL?
    /// Lifetime of the device code, in seconds.
    public let expiresIn: TimeInterval
    /// Minimum polling interval, in seconds.
    public let interval: TimeInterval?

    public init(
        deviceCode: String,
        userCode: String,
        verificationURI: URL,
        verificationURIComplete: URL? = nil,
        expiresIn: TimeInterval,
        interval: TimeInterval? = nil
    ) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationURI = verificationURI
        self.verificationURIComplete = verificationURIComplete
        self.expiresIn = expiresIn
        self.interval = interval
    }

    enum CodingKeys: String, CodingKey {
        case deviceCode = "device_code"
        case userCode = "user_code"
        case verificationURI = "verification_uri"
        case verificationURIComplete = "verification_uri_complete"
        case expiresIn = "expires_in"
        case interval
    }
}

/// The approved outcome of the device flow. The provider's `access_token`
/// is an opaque Better Auth session token with a sliding server-side expiry.
public struct DeviceTokenGrant: Sendable, Equatable {
    public let sessionToken: String
    public let expiresAt: Date?

    public init(sessionToken: String, expiresAt: Date?) {
        self.sessionToken = sessionToken
        self.expiresAt = expiresAt
    }
}

/// One poll of the device token endpoint (RFC 8628 §3.4/§3.5). Terminal
/// failures (`access_denied`, `expired_token`) are thrown as `AuthError`.
public enum DevicePollOutcome: Sendable, Equatable {
    case granted(DeviceTokenGrant)
    case authorizationPending
    case slowDown
}

/// What the UI shows while the browser approval is pending.
public struct DeviceAuthorizationPrompt: Sendable, Equatable {
    public let userCode: String
    public let verificationURI: URL
    public let verificationURIComplete: URL?

    public init(userCode: String, verificationURI: URL, verificationURIComplete: URL?) {
        self.userCode = userCode
        self.verificationURI = verificationURI
        self.verificationURIComplete = verificationURIComplete
    }

    /// The URL to open: pre-filled variant when available.
    public var browserURL: URL { verificationURIComplete ?? verificationURI }
}
