import Foundation

/// The session credential persisted across launches.
public struct StoredSession: Codable, Sendable, Equatable {
    /// Opaque Better Auth session token, sent as `Authorization: Bearer`.
    public var sessionToken: String
    /// Sliding server-side expiry as of the last time the session was
    /// verified. Display-only: the provider is the authority, so an expired
    /// date never blocks a restore.
    public var expiresAt: Date?

    public init(sessionToken: String, expiresAt: Date?) {
        self.sessionToken = sessionToken
        self.expiresAt = expiresAt
    }
}
