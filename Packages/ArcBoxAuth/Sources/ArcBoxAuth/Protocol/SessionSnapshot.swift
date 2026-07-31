import Foundation

/// The provider's view of a session, from `GET {issuer}/get-session`.
///
/// A syntactically valid but revoked or expired token yields `null` (mapped
/// to `nil` by the client), which is the authoritative "signed out" signal.
public struct SessionSnapshot: Sendable, Equatable, Decodable {
    public let session: SessionDetails
    public let user: SessionUser

    public init(session: SessionDetails, user: SessionUser) {
        self.session = session
        self.user = user
    }
}

public struct SessionDetails: Sendable, Equatable, Decodable {
    /// Sliding expiry; the provider extends it as the session is used.
    public let expiresAt: Date?

    public init(expiresAt: Date?) {
        self.expiresAt = expiresAt
    }
}

public struct SessionUser: Sendable, Equatable, Decodable {
    public let id: String
    public let name: String?
    public let email: String?
    public let emailVerified: Bool?
    /// Avatar URL as sent by the provider; may be absent or empty.
    public let image: String?

    public init(
        id: String,
        name: String? = nil,
        email: String? = nil,
        emailVerified: Bool? = nil,
        image: String? = nil
    ) {
        self.id = id
        self.name = name
        self.email = email
        self.emailVerified = emailVerified
        self.image = image
    }
}
