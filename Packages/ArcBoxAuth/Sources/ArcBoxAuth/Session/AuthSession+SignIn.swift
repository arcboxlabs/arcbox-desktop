import AuthenticationServices
import Foundation
import SwiftUI

extension AuthSession {
    /// Everything needed to finish the code exchange once the browser
    /// redirects back, held while the browser leg is in flight.
    struct PendingAuthorization {
        let state: String
        let verifier: String
        let nonce: String
        let endpoints: OIDCEndpoints
    }

    /// Runs the full browser-based Authorization Code + PKCE flow.
    ///
    /// `WebAuthenticationSession` exists only as a SwiftUI environment value,
    /// so the calling view passes it in; both are MainActor-bound. Failures
    /// land in `status` rather than being thrown; a user-cancelled browser
    /// sheet quietly returns to `.signedOut`.
    ///
    /// The redirect can come back two ways: the web session returns it
    /// directly, or — when sign-in finishes in an external browser — Launch
    /// Services delivers it as a deep link (`handleAuthorizationCallback`).
    /// Both funnel into `finishAuthorization`; whichever arrives first wins.
    public func signIn(using webSession: WebAuthenticationSession) async {
        guard status != .signingIn else { return }
        status = .signingIn
        do {
            let authorizationURL = try await beginAuthorization()
            guard let scheme = OIDCClientConfiguration.redirectURI.scheme else {
                throw OIDCError.invalidCallbackURL
            }
            let callbackURL = try await webSession.authenticate(
                using: authorizationURL,
                callback: .customScheme(scheme),
                additionalHeaderFields: [:])
            await finishAuthorization(callbackURL: callbackURL)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            // The user may have dismissed the sheet to finish in an external
            // browser: keep `pendingAuthorization` so a deep-link callback
            // can still complete, but stop showing progress. Don't clobber a
            // session a deep link already established.
            if status == .signingIn { status = .signedOut }
        } catch let error as OIDCError {
            ClientLog.auth.error("Sign-in failed: \(String(describing: error))")
            status = .error(error.userMessage)
        } catch {
            ClientLog.auth.error("Sign-in failed: \(String(describing: error))")
            status = .error(error.localizedDescription)
        }
    }

    /// Completes sign-in from an OAuth redirect delivered as a deep link
    /// (`onOpenURL`) rather than through the web session — the path taken
    /// when the authorization leg ends in an external browser.
    ///
    /// Returns `false` when the URL is not this app's OAuth redirect, so the
    /// caller can route it as an ordinary deep link. A redirect with no
    /// sign-in in flight (stale or replayed callback) is consumed and
    /// ignored.
    @discardableResult
    public func handleAuthorizationCallback(_ url: URL) async -> Bool {
        let redirect = OIDCClientConfiguration.redirectURI
        guard let scheme = url.scheme, let expectedScheme = redirect.scheme,
            scheme.caseInsensitiveCompare(expectedScheme) == .orderedSame,
            url.path(percentEncoded: false) == redirect.path(percentEncoded: false)
        else { return false }
        guard pendingAuthorization != nil else {
            ClientLog.auth.warning("Ignoring OAuth callback: no sign-in in progress")
            return true
        }
        status = .signingIn
        await finishAuthorization(callbackURL: url)
        return true
    }

    /// Builds the authorization request and records the context needed to
    /// finish it. Split from `signIn(using:)` so tests can drive the flow
    /// without a `WebAuthenticationSession`.
    func beginAuthorization() async throws -> URL {
        let endpoints = try await resolvedEndpoints()
        let pkce = PKCE.generateCodePair()
        let state = PKCE.generateRandomToken()
        let nonce = PKCE.generateRandomToken()
        let authorizationURL = try OIDCAuthorizationURLBuilder.makeURL(
            endpoints: endpoints,
            configuration: configuration,
            pkce: pkce,
            state: state,
            nonce: nonce)
        pendingAuthorization = PendingAuthorization(
            state: state, verifier: pkce.verifier, nonce: nonce, endpoints: endpoints)
        return authorizationURL
    }

    /// Single completion funnel: consumes `pendingAuthorization` exactly once
    /// (MainActor serialization makes take-then-clear race-free) and maps
    /// failures into `status`. A second arrival is a no-op.
    private func finishAuthorization(callbackURL: URL) async {
        guard let pending = pendingAuthorization else { return }
        pendingAuthorization = nil
        do {
            try await completeSignIn(
                callbackURL: callbackURL,
                expectedState: pending.state,
                verifier: pending.verifier,
                nonce: pending.nonce,
                endpoints: pending.endpoints)
        } catch let error as OIDCError {
            ClientLog.auth.error("Sign-in failed: \(String(describing: error))")
            status = .error(error.userMessage)
        } catch {
            ClientLog.auth.error("Sign-in failed: \(String(describing: error))")
            status = .error(error.localizedDescription)
        }
    }

    /// Security-critical completion: validates `state` (CSRF) and `nonce`,
    /// exchanges the code, persists, and publishes the session. Split from
    /// `signIn(using:)` so it is unit-testable — `WebAuthenticationSession`
    /// cannot be constructed in tests.
    func completeSignIn(
        callbackURL: URL,
        expectedState: String,
        verifier: String,
        nonce: String,
        endpoints: OIDCEndpoints
    ) async throws {
        let query = Self.queryParameters(of: callbackURL)
        if let errorCode = query["error"] {
            throw OIDCError.authorizationDenied(query["error_description"] ?? errorCode)
        }
        guard let state = query["state"], state == expectedState else {
            throw OIDCError.stateMismatch
        }
        guard let code = query["code"], !code.isEmpty else {
            throw OIDCError.missingAuthorizationCode
        }
        let response = try await provider.exchangeCode(
            code, verifier: verifier, configuration: configuration, endpoints: endpoints)
        if let idToken = response.idToken {
            let claims = try IDTokenClaims.decode(idToken: idToken)
            if let tokenNonce = claims.nonce, tokenNonce != nonce {
                throw OIDCError.invalidIDToken
            }
        }
        adopt(Self.merge(response: response, into: nil), persist: true)
        await loadUserInfo()
    }

    private static func queryParameters(of url: URL) -> [String: String] {
        guard let items = URLComponents(url: url, resolvingAgainstBaseURL: false)?.queryItems
        else { return [:] }
        return Dictionary(
            items.compactMap { item in item.value.map { (item.name, $0) } },
            uniquingKeysWith: { first, _ in first }
        )
    }
}
