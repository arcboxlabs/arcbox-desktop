public enum AuthStatus: Sendable, Equatable {
    case signedOut
    case signingIn
    case signedIn
    /// Sign-in failed; carries a user-presentable message.
    case error(String)
}

/// Who is signed in, decoded from the ID token for display purposes only.
public struct AuthIdentity: Sendable, Equatable {
    public let subject: String
    public let email: String?
    public let name: String?

    public init(subject: String, email: String?, name: String?) {
        self.subject = subject
        self.email = email
        self.name = name
    }

    public var displayName: String { name ?? email ?? subject }
}
