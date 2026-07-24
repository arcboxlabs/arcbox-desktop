import AppKit
import Foundation
import Observation

/// Observable session state for platform sign-in: restores from the Keychain
/// when started, hands out the session bearer token, and signs out.
///
/// The session token has a sliding server-side expiry that the provider
/// extends on use, so there is no client-side refresh: a token is valid
/// until the provider says otherwise (`refreshSession()`), and a platform
/// 401 means the user must sign in again.
///
/// The interactive device-authorization leg lives in `AuthSession+SignIn.swift`.
@Observable
@MainActor
public final class AuthSession: AccessTokenProviding {
    public internal(set) var status: AuthStatus = .signedOut
    public internal(set) var identity: AuthIdentity?
    /// The browser-approval prompt to display while sign-in is in flight.
    public internal(set) var deviceAuthorization: DeviceAuthorizationPrompt?

    public let configuration: AuthClientConfiguration

    let provider: any AuthProviding
    private let tokenStore: any TokenStoring
    @ObservationIgnored var session: StoredSession?
    @ObservationIgnored private var restorationTask: Task<Void, Never>?
    @ObservationIgnored private var didAttemptRestore = false
    @ObservationIgnored var signInTask: Task<Void, Never>?
    /// Sleep seam so tests drive the polling loop without real delays.
    @ObservationIgnored let sleeper: @Sendable (Duration) async throws -> Void
    /// Browser seam so tests observe the verification URL being opened.
    @ObservationIgnored let openURL: @MainActor (URL) -> Void

    public init(
        configuration: AuthClientConfiguration = .current,
        provider: any AuthProviding = BetterAuthClient(),
        tokenStore: any TokenStoring = KeychainTokenStore(),
        sleeper: @escaping @Sendable (Duration) async throws -> Void = {
            try await Task.sleep(for: $0)
        },
        openURL: (@MainActor (URL) -> Void)? = nil
    ) {
        self.configuration = configuration
        self.provider = provider
        self.tokenStore = tokenStore
        self.sleeper = sleeper
        self.openURL = openURL ?? { NSWorkspace.shared.open($0) }
    }

    /// Rehydrates state from the Keychain; no network. The provider owns
    /// expiry, so any stored token restores the session — `refreshSession()`
    /// signs out if the provider no longer honors it.
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
        guard let session else { throw AuthError.notSignedIn }
        return session.sessionToken
    }

    // MARK: - Session refresh

    /// Verifies the session with the provider and publishes the account
    /// identity (this is the sole source of name/email/avatar). A provider
    /// that authoritatively reports no session signs the user out; transport
    /// failures keep the local session. Runs automatically after sign-in;
    /// the app also calls it after a restored launch.
    public func refreshSession() async {
        guard status == .signedIn, let token = session?.sessionToken else { return }
        do {
            guard
                let snapshot = try await provider.session(
                    token: token, configuration: configuration)
            else {
                ClientLog.auth.info("Provider no longer honors the stored session; signing out")
                await forgetSession()
                return
            }
            // The session may have been signed out or replaced while the
            // request was in flight.
            guard session?.sessionToken == token else { return }
            identity = AuthIdentity(
                subject: snapshot.user.id,
                email: normalized(snapshot.user.email),
                name: normalized(snapshot.user.name),
                avatarURL: normalized(snapshot.user.image).flatMap(URL.init(string:)),
                emailVerified: snapshot.user.emailVerified)
            if let expiresAt = snapshot.session.expiresAt {
                let updated = StoredSession(sessionToken: token, expiresAt: expiresAt)
                session = updated
                await persist(updated)
            }
            ClientLog.auth.info(
                "Session verified for \(snapshot.user.id, privacy: .private(mask: .hash))")
        } catch {
            ClientLog.auth.warning("Session refresh failed: \(String(describing: error))")
        }
    }

    // MARK: - Sign-out

    /// Revokes the session server-side (best-effort) and clears local state.
    /// Sign-out must never block on an unreachable provider.
    public func signOut() async {
        cancelSignIn()
        if let token = session?.sessionToken {
            do {
                try await provider.signOut(token: token, configuration: configuration)
            } catch {
                ClientLog.auth.warning(
                    "Server-side sign-out failed: \(String(describing: error))")
            }
        }
        await forgetSession()
    }

    // MARK: - Internal (shared with AuthSession+SignIn, tested via @testable)

    /// Publishes a stored session as the current one. Identity arrives
    /// separately via `refreshSession()`.
    func adopt(_ stored: StoredSession) {
        session = stored
        status = .signedIn
    }

    /// Persists the session without blocking the main actor. Persistence is
    /// best-effort so a Keychain failure does not discard a valid live session.
    func persist(_ stored: StoredSession) async {
        do {
            try await tokenStore.save(stored)
        } catch {
            ClientLog.auth.error("Failed to persist session: \(String(describing: error))")
        }
    }

    func forgetSession() async {
        session = nil
        identity = nil
        deviceAuthorization = nil
        status = .signedOut
        do {
            try await tokenStore.clear()
        } catch {
            ClientLog.auth.error("Failed to clear Keychain: \(String(describing: error))")
        }
    }

    private func normalized(_ value: String?) -> String? {
        guard let value, !value.isEmpty else { return nil }
        return value
    }
}
