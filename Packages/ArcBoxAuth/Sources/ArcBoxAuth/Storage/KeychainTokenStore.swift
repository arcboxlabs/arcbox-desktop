import Foundation
import Security

/// Persists the session as one generic-password item holding a JSON blob,
/// so every save is atomic. The app is unsandboxed; the default per-app
/// keychain access applies without any entitlement.
public actor KeychainTokenStore: TokenStoring {
    private let service: String
    private let account: String

    /// `service` identifies the persisted item — treat the default as a
    /// stable format once shipped. It predates the device-grant flow, so
    /// items written by earlier builds share it; `load()` clears any blob
    /// it cannot decode (the old OIDC token-set shape) instead of failing.
    public init(service: String = "com.arcboxlabs.desktop.oidc", account: String = "default") {
        self.service = service
        self.account = account
    }

    public func save(_ session: StoredSession) throws {
        let data = try JSONEncoder().encode(session)
        let update = [kSecValueData as String: data]
        let status = SecItemUpdate(baseQuery as CFDictionary, update as CFDictionary)
        switch status {
        case errSecSuccess:
            return
        case errSecItemNotFound:
            var query = baseQuery
            query[kSecValueData as String] = data
            let addStatus = SecItemAdd(query as CFDictionary, nil)
            guard addStatus == errSecSuccess else {
                throw KeychainError.unhandledStatus(addStatus)
            }
        default:
            throw KeychainError.unhandledStatus(status)
        }
    }

    public func load() throws -> StoredSession? {
        var query = baseQuery
        query[kSecReturnData as String] = true
        query[kSecMatchLimit as String] = kSecMatchLimitOne
        var result: CFTypeRef?
        let status = SecItemCopyMatching(query as CFDictionary, &result)
        switch status {
        case errSecSuccess:
            guard let data = result as? Data,
                let session = try? JSONDecoder().decode(StoredSession.self, from: data)
            else {
                // Undecodable blob — a pre-device-flow token set or
                // corruption. Either way it cannot authenticate anything;
                // clear it so the user starts cleanly signed out.
                try clear()
                return nil
            }
            return session
        case errSecItemNotFound:
            return nil
        default:
            throw KeychainError.unhandledStatus(status)
        }
    }

    public func clear() throws {
        let status = SecItemDelete(baseQuery as CFDictionary)
        guard status == errSecSuccess || status == errSecItemNotFound else {
            throw KeychainError.unhandledStatus(status)
        }
    }

    private var baseQuery: [String: Any] {
        [
            kSecClass as String: kSecClassGenericPassword,
            kSecAttrService as String: service,
            kSecAttrAccount as String: account,
        ]
    }
}
