import Foundation
import Testing

@testable import ArcBoxAuth

/// Exercises the real Keychain with a unique per-test service name; every
/// test cleans up its item so repeated runs never leak into the login keychain.
struct KeychainTokenStoreTests {
    private let store = KeychainTokenStore(
        service: "com.arcboxlabs.desktop.oidc.tests.\(UUID().uuidString)")

    private let tokens = StoredTokens(
        accessToken: "access-1",
        refreshToken: "refresh-1",
        idToken: "id-1",
        expiresAt: Date(timeIntervalSince1970: 1_751_900_000)
    )

    @Test func roundTripsATokenSet() async throws {
        try await withCleanup {
            try await store.save(tokens)
            #expect(try await store.load() == tokens)
        }
    }

    @Test func loadReturnsNilWhenEmpty() async throws {
        #expect(try await store.load() == nil)
    }

    @Test func saveOverwritesTheExistingItem() async throws {
        try await withCleanup {
            try await store.save(tokens)
            var updated = tokens
            updated.accessToken = "access-2"
            updated.refreshToken = nil
            try await store.save(updated)
            #expect(try await store.load() == updated)
        }
    }

    @Test func clearRemovesTheItemAndIsIdempotent() async throws {
        try await store.save(tokens)
        try await store.clear()
        #expect(try await store.load() == nil)
        try await store.clear()
    }

    private func withCleanup(_ operation: () async throws -> Void) async throws {
        do {
            try await operation()
        } catch {
            try? await store.clear()
            throw error
        }
        try await store.clear()
    }
}
