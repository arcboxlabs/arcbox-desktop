import Foundation

/// Profile claims from the userinfo endpoint (OIDC Core §5.3).
///
/// The platform IdP never embeds profile claims in ID tokens, so this is the
/// sole source of name/email/avatar. Every field except `subject` is
/// scope-gated and optional: `name`/`picture` require `profile`,
/// `email`/`emailVerified` require `email`, and the provider omits claims
/// whose backing user fields are unset (e.g. no `picture` until the account
/// has an avatar).
public struct OIDCUserInfo: Sendable, Equatable, Decodable {
    public let subject: String
    public let name: String?
    public let email: String?
    public let emailVerified: Bool?
    public let picture: URL?

    public init(
        subject: String,
        name: String? = nil,
        email: String? = nil,
        emailVerified: Bool? = nil,
        picture: URL? = nil
    ) {
        self.subject = subject
        self.name = name
        self.email = email
        self.emailVerified = emailVerified
        self.picture = picture
    }

    enum CodingKeys: String, CodingKey {
        case subject = "sub"
        case name
        case email
        case emailVerified = "email_verified"
        case picture
    }
}
