import AuthenticationServices
import Foundation
import SwiftUI

extension AuthSession {
    /// Runs the full browser-based Authorization Code + PKCE flow.
    ///
    /// `WebAuthenticationSession` exists only as a SwiftUI environment value,
    /// so the calling view passes it in; both are MainActor-bound. Failures
    /// land in `status` rather than being thrown; a user-cancelled browser
    /// sheet quietly returns to `.signedOut`.
    public func signIn(using webSession: WebAuthenticationSession) async {
        guard status != .signingIn else { return }
        status = .signingIn
        do {
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
            guard let scheme = OIDCClientConfiguration.redirectURI.scheme else {
                throw OIDCError.invalidCallbackURL
            }
            let callbackURL = try await webSession.authenticate(
                using: authorizationURL,
                callback: .customScheme(scheme),
                additionalHeaderFields: [:])
            try await completeSignIn(
                callbackURL: callbackURL,
                expectedState: state,
                verifier: pkce.verifier,
                nonce: nonce,
                endpoints: endpoints)
        } catch let error as ASWebAuthenticationSessionError where error.code == .canceledLogin {
            status = .signedOut
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
