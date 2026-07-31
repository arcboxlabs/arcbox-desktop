/// The seam platform API clients consume: ask for a currently valid access
/// token — refreshed under the hood when needed — without depending on
/// SwiftUI or Observation.
public protocol AccessTokenProviding: Sendable {
    /// Throws `AuthError.notSignedIn` when there is no session.
    func accessToken() async throws -> String
}
