/// Persistence seam for the session credential, so `AuthSession` can be
/// tested with an in-memory fake instead of the real Keychain.
public protocol TokenStoring: Sendable {
    func save(_ session: StoredSession) async throws
    func load() async throws -> StoredSession?
    func clear() async throws
}
