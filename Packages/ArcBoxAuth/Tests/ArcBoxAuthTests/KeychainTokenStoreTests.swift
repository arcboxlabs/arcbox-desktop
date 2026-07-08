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

    @Test func roundTripsATokenSet() throws {
        defer { try? store.clear() }
        try store.save(tokens)
        #expect(try store.load() == tokens)
    }

    @Test func loadReturnsNilWhenEmpty() throws {
        #expect(try store.load() == nil)
    }

    @Test func saveOverwritesTheExistingItem() throws {
        defer { try? store.clear() }
        try store.save(tokens)
        var updated = tokens
        updated.accessToken = "access-2"
        updated.refreshToken = nil
        try store.save(updated)
        #expect(try store.load() == updated)
    }

    @Test func clearRemovesTheItemAndIsIdempotent() throws {
        try store.save(tokens)
        try store.clear()
        #expect(try store.load() == nil)
        try store.clear()
    }
}
