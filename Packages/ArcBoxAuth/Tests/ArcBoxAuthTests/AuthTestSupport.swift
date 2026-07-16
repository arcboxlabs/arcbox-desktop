import Foundation
import os

@testable import ArcBoxAuth

enum AuthTestSupport {
    static let configuration = AuthClientConfiguration(
        issuerURL: URL(string: "https://idp.example.com/api/auth")!,
        clientID: "test-client"
    )

    static func grant(
        expiresIn: TimeInterval = 1800,
        interval: TimeInterval? = 5
    ) -> DeviceCodeGrant {
        DeviceCodeGrant(
            deviceCode: "device-1",
            userCode: "ABCD1234",
            verificationURI: URL(string: "https://idp.example.com/device")!,
            verificationURIComplete: URL(
                string: "https://idp.example.com/device?user_code=ABCD1234"),
            expiresIn: expiresIn,
            interval: interval
        )
    }

    static func snapshot(
        subject: String = "user-1",
        name: String? = "Ada",
        email: String? = "ada@example.com",
        expiresAt: Date? = Date(timeIntervalSince1970: 4_102_444_800)
    ) -> SessionSnapshot {
        SessionSnapshot(
            session: SessionDetails(expiresAt: expiresAt),
            user: SessionUser(
                id: subject, name: name, email: email, emailVerified: true, image: nil)
        )
    }
}

final class InMemoryTokenStore: TokenStoring {
    private struct State {
        var stored: StoredSession?
        var saveCalls = 0
        var loadCalls = 0
        var clearCalls = 0
        var shouldFailLoading = false
    }

    enum Failure: Error {
        case loadFailed
    }

    private let storage: OSAllocatedUnfairLock<State>

    var stored: StoredSession? { storage.withLock { $0.stored } }
    var saveCalls: Int { storage.withLock { $0.saveCalls } }
    var loadCalls: Int { storage.withLock { $0.loadCalls } }
    var clearCalls: Int { storage.withLock { $0.clearCalls } }

    init(initial: StoredSession? = nil) {
        storage = OSAllocatedUnfairLock(initialState: State(stored: initial))
    }

    func failLoading() {
        storage.withLock { $0.shouldFailLoading = true }
    }

    func save(_ session: StoredSession) throws {
        storage.withLock {
            $0.saveCalls += 1
            $0.stored = session
        }
    }

    func load() throws -> StoredSession? {
        let result = storage.withLock {
            $0.loadCalls += 1
            return ($0.shouldFailLoading, $0.stored)
        }
        if result.0 { throw Failure.loadFailed }
        return result.1
    }

    func clear() throws {
        storage.withLock {
            $0.clearCalls += 1
            $0.stored = nil
        }
    }
}

/// Scripted provider: poll outcomes are consumed in order; the last entry
/// repeats for any further polls.
final class FakeAuthProvider: AuthProviding {
    struct State {
        var deviceCodeResult: Result<DeviceCodeGrant, AuthError> = .success(
            AuthTestSupport.grant())
        var pollScript: [Result<DevicePollOutcome, AuthError>] = [
            .success(.granted(DeviceTokenGrant(sessionToken: "session-1", expiresAt: nil)))
        ]
        var sessionResult: Result<SessionSnapshot?, AuthError> = .success(
            AuthTestSupport.snapshot())
        var signOutError: AuthError?
        var deviceCodeCalls = 0
        var pollCalls = 0
        var sessionCalls = 0
        var signOutCalls = 0
        var signOutTokens: [String] = []
    }

    private let state = OSAllocatedUnfairLock(initialState: State())

    var deviceCodeCalls: Int { state.withLock { $0.deviceCodeCalls } }
    var pollCalls: Int { state.withLock { $0.pollCalls } }
    var sessionCalls: Int { state.withLock { $0.sessionCalls } }
    var signOutCalls: Int { state.withLock { $0.signOutCalls } }
    var signOutTokens: [String] { state.withLock { $0.signOutTokens } }

    func configure(_ change: @Sendable (inout State) -> Void) {
        state.withLock { change(&$0) }
    }

    func requestDeviceCode(
        configuration: AuthClientConfiguration
    ) async throws -> DeviceCodeGrant {
        try state.withLock { s in
            s.deviceCodeCalls += 1
            return s.deviceCodeResult
        }.get()
    }

    func pollDeviceToken(
        deviceCode: String,
        configuration: AuthClientConfiguration
    ) async throws -> DevicePollOutcome {
        try state.withLock { s in
            s.pollCalls += 1
            let result = s.pollScript.first ?? .failure(.notSignedIn)
            if s.pollScript.count > 1 { s.pollScript.removeFirst() }
            return result
        }.get()
    }

    func session(
        token: String,
        configuration: AuthClientConfiguration
    ) async throws -> SessionSnapshot? {
        try state.withLock { s in
            s.sessionCalls += 1
            return s.sessionResult
        }.get()
    }

    func signOut(token: String, configuration: AuthClientConfiguration) async throws {
        let error = state.withLock { s in
            s.signOutCalls += 1
            s.signOutTokens.append(token)
            return s.signOutError
        }
        if let error { throw error }
    }
}

/// Records slept intervals; can gate the loop so tests observe mid-poll state.
final class RecordingSleeper: Sendable {
    private let state = OSAllocatedUnfairLock(initialState: [Duration]())

    var slept: [Duration] { state.withLock { $0 } }

    @Sendable func sleep(_ duration: Duration) async throws {
        state.withLock { $0.append(duration) }
        await Task.yield()
        try Task.checkCancellation()
    }
}

/// Captures URLs the session asked the browser to open.
@MainActor
final class BrowserSpy {
    private(set) var opened: [URL] = []

    func open(_ url: URL) {
        opened.append(url)
    }
}
