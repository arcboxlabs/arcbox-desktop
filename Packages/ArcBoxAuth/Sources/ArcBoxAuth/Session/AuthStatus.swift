import Foundation

public enum AuthStatus: Sendable, Equatable {
    case signedOut
    case restoring
    case signingIn
    case signedIn
    /// Sign-in failed; carries a user-presentable message.
    case error(String)
}

/// Who is signed in, for display purposes only. Sourced from the provider's
/// session endpoint via `AuthSession.refreshSession()`.
public struct AuthIdentity: Sendable, Equatable {
    public let subject: String
    public let email: String?
    public let name: String?
    public let avatarURL: URL?
    public let emailVerified: Bool?

    public init(
        subject: String,
        email: String?,
        name: String?,
        avatarURL: URL? = nil,
        emailVerified: Bool? = nil
    ) {
        self.subject = subject
        self.email = email
        self.name = name
        self.avatarURL = avatarURL
        self.emailVerified = emailVerified
    }

    public var displayName: String { name ?? email ?? subject }
}
