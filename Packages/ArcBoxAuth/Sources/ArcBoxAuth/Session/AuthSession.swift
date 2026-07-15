import Foundation
import Observation

/// Observable session state for platform sign-in: restores from the Keychain
/// when started, hands out valid access tokens (refreshing lazily), and signs out.
///
/// The interactive browser leg lives in `AuthSession+SignIn.swift`.
@Observable
@MainActor
public final class AuthSession: AccessTokenProviding {
    public internal(set) var status: AuthStatus = .signedOut
    public private(set) var identity: AuthIdentity?
    /// When the current access token expires, for display in the Account UI.
    public private(set) var accessTokenExpiresAt: Date?

    public let configuration: OIDCClientConfiguration

    let provider: any OIDCProviding
    private let tokenStore: any TokenStoring
    @ObservationIgnored private var tokens: StoredTokens?
    @ObservationIgnored private var endpoints: OIDCEndpoints?
    @ObservationIgnored private var refreshTask: Task<StoredTokens, Error>?
    @ObservationIgnored private var restorationTask: Task<Void, Never>?
    @ObservationIgnored private var didAttemptRestore = false
    /// Context for the in-flight browser leg, consumed exactly once by
    /// whichever completion path returns first: the web-session result or a
    /// deep-link callback (see `AuthSession+SignIn.swift`).
    @ObservationIgnored var pendingAuthorization: PendingAuthorization?

    /// Refresh this long before nominal expiry to absorb clock skew.
    private static let expiryLeeway: TimeInterval = 60
    /// Used when the token response omits the RECOMMENDED `expires_in`.
    private static let defaultTokenLifetime: TimeInterval = 3600

    public init(
        configuration: OIDCClientConfiguration = .current,
        provider: any OIDCProviding = OIDCClient(),
        tokenStore: any TokenStoring = KeychainTokenStore()
    ) {
        self.configuration = configuration
        self.provider = provider
        self.tokenStore = tokenStore
    }

    /// Rehydrates state from the Keychain; no network. An expired access
    /// token still restores the session — it refreshes on first use.
    public func restoreSession() async {
        if let restorationTask {
            await restorationTask.value
            return
        }
        guard !didAttemptRestore else { return }
        didAttemptRestore = true
        guard status == .signedOut else { return }
        status = .restoring

        let task = Task { [weak self] in
            guard let self else { return }
            await performSessionRestore()
        }
        restorationTask = task
        await task.value
        restorationTask = nil
    }

    private func performSessionRestore() async {
        do {
            let stored = try await tokenStore.load()
            guard status == .restoring else { return }
            guard let stored else {
                status = .signedOut
                return
            }
            adopt(stored)
        } catch {
            guard status == .restoring else { return }
            status = .signedOut
            ClientLog.auth.error(
                "Failed to restore session from Keychain: \(String(describing: error))")
        }
    }

    // MARK: - AccessTokenProviding

    public func accessToken() async throws -> String {
        guard let tokens else { throw OIDCError.notSignedIn }
        if tokens.expiresAt > Date().addingTimeInterval(Self.expiryLeeway) {
            return tokens.accessToken
        }
        return try await refreshedTokens().accessToken
    }

    // MARK: - UserInfo

    /// Fetches profile claims from the userinfo endpoint and publishes them
    /// as `identity`. The platform IdP never embeds profile claims in ID
    /// tokens, so this is the only source of name/email/avatar. Best-effort:
    /// failures log and keep the existing identity. Runs automatically after
    /// sign-in; the app also calls it after a restored launch.
    public func loadUserInfo() async {
        guard status == .signedIn else { return }
        do {
            let endpoints = try await resolvedEndpoints()
            guard let endpoint = endpoints.userinfoEndpoint else {
                ClientLog.auth.warning("Provider advertises no userinfo endpoint")
                return
            }
            let info = try await provider.userInfo(
                accessToken: try await accessToken(), endpoint: endpoint)
            identity = AuthIdentity(
                subject: info.subject,
                email: info.email ?? identity?.email,
                name: info.name ?? identity?.name,
                avatarURL: info.picture,
                emailVerified: info.emailVerified)
            ClientLog.auth.info(
                "UserInfo loaded for \(info.subject, privacy: .private(mask: .hash))")
        } catch {
            ClientLog.auth.warning("UserInfo fetch failed: \(String(describing: error))")
        }
    }

    // MARK: - Sign-out

    /// Clears the session locally and best-effort revokes the refresh token.
    /// Revocation is only attempted when discovery already ran this launch —
    /// sign-out must never block on an unreachable issuer.
    public func signOut() async {
        refreshTask?.cancel()
        refreshTask = nil
        if let refreshToken = tokens?.refreshToken,
            let endpoint = endpoints?.revocationEndpoint
        {
            do {
                try await provider.revoke(
                    token: refreshToken,
                    tokenTypeHint: "refresh_token",
                    configuration: configuration,
                    endpoint: endpoint)
            } catch {
                ClientLog.auth.warning("Token revocation failed: \(String(describing: error))")
            }
        }
        await forgetSession()
    }

    // MARK: - Internal (shared with AuthSession+SignIn, tested via @testable)

    func resolvedEndpoints() async throws -> OIDCEndpoints {
        if let endpoints { return endpoints }
        let discovered = try await provider.discover(issuer: configuration.issuerURL)
        endpoints = discovered
        return discovered
    }

    /// Publishes a token set as the current session.
    func adopt(_ stored: StoredTokens) {
        tokens = stored
        accessTokenExpiresAt = stored.expiresAt
        if let idToken = stored.idToken,
            let claims = try? IDTokenClaims.decode(idToken: idToken)
        {
            identity = AuthIdentity(subject: claims.subject, email: claims.email, name: claims.name)
        }
        status = .signedIn
    }

    /// Persists a token set without blocking the main actor. Persistence is
    /// best-effort so a Keychain failure does not discard a valid live session.
    func persist(_ stored: StoredTokens) async {
        do {
            try await tokenStore.save(stored)
        } catch {
            ClientLog.auth.error("Failed to persist tokens: \(String(describing: error))")
        }
    }

    static func merge(response: TokenResponse, into current: StoredTokens?) -> StoredTokens {
        StoredTokens(
            accessToken: response.accessToken,
            // Providers may rotate the refresh token; keep the old one when absent.
            refreshToken: response.refreshToken ?? current?.refreshToken,
            idToken: response.idToken ?? current?.idToken,
            expiresAt: Date().addingTimeInterval(response.expiresIn ?? Self.defaultTokenLifetime)
        )
    }

    // MARK: - Private

    /// De-duplicates concurrent refreshes: the MainActor serial executor plus
    /// no `await` between the check and the store makes this race-free.
    private func refreshedTokens() async throws -> StoredTokens {
        if let refreshTask { return try await refreshTask.value }
        let task = Task { try await performRefresh() }
        refreshTask = task
        defer { refreshTask = nil }
        return try await task.value
    }

    private func performRefresh() async throws -> StoredTokens {
        guard let current = tokens else { throw OIDCError.notSignedIn }
        guard let refreshToken = current.refreshToken else {
            throw OIDCError.missingRefreshToken
        }
        let endpoints = try await resolvedEndpoints()
        do {
            let response = try await provider.refresh(
                refreshToken: refreshToken, configuration: configuration, endpoints: endpoints)
            let updated = Self.merge(response: response, into: current)
            try Task.checkCancellation()
            guard tokens == current else { throw CancellationError() }
            await persist(updated)
            try Task.checkCancellation()
            guard tokens == current else { throw CancellationError() }
            adopt(updated)
            return updated
        } catch let error as OIDCError {
            if case .tokenRequestFailed(let status, _) = error, status == 400 || status == 401 {
                // invalid_grant: the refresh token is dead — the session is over.
                await forgetSession()
                throw OIDCError.notSignedIn
            }
            throw error
        }
    }

    private func forgetSession() async {
        tokens = nil
        identity = nil
        accessTokenExpiresAt = nil
        status = .signedOut
        do {
            try await tokenStore.clear()
        } catch {
            ClientLog.auth.error("Failed to clear Keychain: \(String(describing: error))")
        }
    }
}
