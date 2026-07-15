/// Persistence seam for the token set, so `AuthSession` can be tested with an
/// in-memory fake instead of the real Keychain.
public protocol TokenStoring: Sendable {
    func save(_ tokens: StoredTokens) async throws
    func load() async throws -> StoredTokens?
    func clear() async throws
}
