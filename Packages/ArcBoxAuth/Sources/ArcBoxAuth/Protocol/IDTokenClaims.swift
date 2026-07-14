import Foundation

/// Claims read from the ID token for display purposes.
///
/// The payload is decoded WITHOUT verifying the JWT signature: these values
/// must never feed an authorization decision. The access token — validated by
/// the platform server-side — is the actual authorization artifact.
public struct IDTokenClaims: Sendable, Equatable {
    public let subject: String
    public let email: String?
    public let name: String?
    public let nonce: String?
    public let expiresAt: Date

    public static func decode(idToken: String) throws -> IDTokenClaims {
        let segments = idToken.components(separatedBy: ".")
        guard segments.count == 3, let payload = Data(base64URLEncoded: segments[1]) else {
            throw OIDCError.invalidIDToken
        }
        let raw: RawClaims
        do {
            raw = try JSONDecoder().decode(RawClaims.self, from: payload)
        } catch {
            throw OIDCError.invalidIDToken
        }
        return IDTokenClaims(
            subject: raw.sub,
            email: raw.email,
            name: raw.name,
            nonce: raw.nonce,
            expiresAt: Date(timeIntervalSince1970: raw.exp)
        )
    }

    private struct RawClaims: Decodable {
        let sub: String
        let email: String?
        let name: String?
        let nonce: String?
        let exp: TimeInterval
    }
}
