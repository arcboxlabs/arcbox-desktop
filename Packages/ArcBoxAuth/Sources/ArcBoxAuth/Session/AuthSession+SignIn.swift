import Foundation

extension AuthSession {
    /// Runs the device-authorization sign-in (RFC 8628): requests a device
    /// code, opens the verification page in the default browser, and polls
    /// the token endpoint until the user approves there. Failures land in
    /// `status` rather than being thrown; cancellation quietly returns to
    /// `.signedOut`.
    ///
    /// While the browser approval is pending, `deviceAuthorization` carries
    /// the user code and verification URL for display.
    public func signIn() async {
        guard status != .restoring, status != .signingIn else { return }
        guard !configuration.isPlaceholder else {
            status = .error(AuthError.notConfigured.userMessage)
            return
        }
        // App-scoped task so `cancelSignIn()` can abandon the polling loop
        // from anywhere (Cancel button, sign-out, termination).
        let task = Task { await performDeviceSignIn() }
        signInTask = task
        await task.value
        if signInTask == task { signInTask = nil }
    }

    /// Abandons an in-flight sign-in. The device code simply expires
    /// server-side; nothing needs revoking.
    public func cancelSignIn() {
        signInTask?.cancel()
    }

    private func performDeviceSignIn() async {
        status = .signingIn
        defer { deviceAuthorization = nil }
        do {
            let grant = try await provider.requestDeviceCode(configuration: configuration)
            try Task.checkCancellation()
            let prompt = DeviceAuthorizationPrompt(
                userCode: grant.userCode,
                verificationURI: grant.verificationURI,
                verificationURIComplete: grant.verificationURIComplete)
            deviceAuthorization = prompt
            openURL(prompt.browserURL)

            let granted = try await pollUntilGranted(grant: grant)
            let stored = StoredSession(
                sessionToken: granted.sessionToken, expiresAt: granted.expiresAt)
            await persist(stored)
            try Task.checkCancellation()
            adopt(stored)
            await refreshSession()
        } catch is CancellationError {
            if status == .signingIn { status = .signedOut }
        } catch let error as AuthError {
            ClientLog.auth.error("Sign-in failed: \(String(describing: error))")
            status = .error(error.userMessage)
        } catch {
            ClientLog.auth.error("Sign-in failed: \(String(describing: error))")
            status = .error(error.localizedDescription)
        }
    }

    /// RFC 8628 §3.5: waits the server-given interval between polls,
    /// stretching by five seconds on `slow_down`, until approval, denial,
    /// or device-code expiry. Elapsed time is accounted from the intervals
    /// actually slept, so the injected sleeper fully drives the loop in tests.
    private func pollUntilGranted(grant: DeviceCodeGrant) async throws -> DeviceTokenGrant {
        var interval = max(grant.interval ?? 5, 1)
        var elapsed: TimeInterval = 0
        while true {
            try await sleeper(.seconds(interval))
            try Task.checkCancellation()
            elapsed += interval
            guard elapsed < grant.expiresIn else { throw AuthError.deviceCodeExpired }

            switch try await provider.pollDeviceToken(
                deviceCode: grant.deviceCode, configuration: configuration)
            {
            case .granted(let token):
                return token
            case .authorizationPending:
                continue
            case .slowDown:
                interval += 5
            }
        }
    }
}
