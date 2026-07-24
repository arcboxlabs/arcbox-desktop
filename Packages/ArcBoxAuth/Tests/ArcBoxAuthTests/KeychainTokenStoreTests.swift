import Foundation
import Testing

@testable import ArcBoxAuth

/// Exercises the real Keychain with a unique per-test service name; every
/// test cleans up its item so repeated runs never leak into the login keychain.
struct KeychainTokenStoreTests {
    private let service = "com.arcboxlabs.desktop.oidc.tests.\(UUID().uuidString)"
    private var store: KeychainTokenStore { KeychainTokenStore(service: service) }

    private let session = StoredSession(
        sessionToken: "session-1",
        expiresAt: Date(timeIntervalSince1970: 1_751_900_000)
    )

    @Test func roundTripsASession() async throws {
        try await withCleanup {
            try await store.save(session)
            #expect(try await store.load() == session)
        }
    }

    @Test func loadReturnsNilWhenEmpty() async throws {
        #expect(try await store.load() == nil)
    }

    @Test func saveOverwritesTheExistingItem() async throws {
        try await withCleanup {
            try await store.save(session)
            var updated = session
            updated.sessionToken = "session-2"
            updated.expiresAt = nil
            try await store.save(updated)
            #expect(try await store.load() == updated)
        }
    }

    @Test func clearRemovesTheItem() async throws {
        try await store.save(session)
        try await store.clear()
        #expect(try await store.load() == nil)
    }

    @Test func clearingAnEmptyStoreIsFine() async throws {
        try await store.clear()
    }

    /// Blobs written by the pre-device-flow OIDC builds cannot authenticate
    /// anything; loading one must self-heal to a clean signed-out state.
    @Test func undecodableLegacyBlobIsClearedOnLoad() async throws {
        try await withCleanup {
            let legacy = Data(
                #"{"accessToken":"jwt","refreshToken":"r","expiresAt":775875577}"#.utf8)
            try saveRaw(legacy)
            #expect(try await store.load() == nil)
            #expect(try loadRaw() == nil)
        }
    }

    // MARK: - Support

    private func withCleanup(_ body: () async throws -> Void) async throws {
        do {
            try await body()
            try await store.clear()
        } catch {
            try? await store.clear()
            throw error
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: "default",
        ]
    }

    private func saveRaw(_ data: Data) throws {
        var query = baseQuery
        query[kSecValueData as String] = data
        let status = SecItemAdd(query as CFDictionary, nil)
        guard status == errSecSuccess else { throw KeychainError.unhandledStatus(status) }
    }

    private func loadRaw() throws -> Data? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess: return result as? Data
        case errSecItemNotFound: return nil
        default: throw KeychainError.unhandledStatus(status)
        }
    }
}
