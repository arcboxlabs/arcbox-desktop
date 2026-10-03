import Foundation

/// Decides which sandbox lifecycle events are worth interrupting the user for.
///
/// A sandbox execution is the one thing users routinely wait on without
/// watching the window, so every failure is surfaced, and successes are
/// surfaced once they have run long enough that the user has plausibly looked
/// away.
struct SandboxNotificationRules {
    /// Successful executions shorter than this are assumed to have finished
    /// while the user was still watching them.
    static let minimumSuccessDuration: TimeInterval = 30

    /// When each sandbox's current execution started, so a completion can be
    /// judged against how long it ran. An execution whose start was never
    /// observed — the app launched partway through it — has no entry.
    private var executionStart: [String: Date] = [:]

    mutating func notification(for event: SandboxEventRecord) -> AppNotification? {
        switch event.kind {
        case .running:
            executionStart[event.sandboxID] = event.timestamp
            return nil

        case .idle:
            return completion(for: event, startedAt: executionStart.removeValue(forKey: event.sandboxID))

        case .failed:
            executionStart.removeValue(forKey: event.sandboxID)
            let reason = Self.attribute("error", of: event)
            return Self.failure(
                event,
                title: "Sandbox failed",
                body: reason.map { "\(Self.name(of: event)) — \($0)" }
                    ?? "\(Self.name(of: event)) stopped with an unrecoverable error."
            )

        case .stopped, .removed:
            executionStart.removeValue(forKey: event.sandboxID)
            return nil

        // A pause suspends the execution rather than ending it, so the start
        // is deliberately kept: the same run continues after `resumed`.
        case .created, .ready, .stopping, .pausing, .paused, .resumed, .unknown:
            return nil
        }
    }

    // MARK: - Private

    /// An execution ended. Failures always notify. A success notifies only when
    /// its start was observed and it ran past the threshold — an unknown
    /// duration stays silent rather than guessing that the user walked away.
    private func completion(for event: SandboxEventRecord, startedAt: Date?) -> AppNotification? {
        let name = Self.name(of: event)

        // On `idle`, "error" means the session broke before an exit was seen.
        if let error = Self.attribute("error", of: event) {
            return Self.failure(event, title: "Sandbox execution failed", body: "\(name) — \(error)")
        }
        if let signal = Self.attribute("signal", of: event) {
            return Self.failure(
                event, title: "Sandbox execution killed", body: "\(name) was killed by \(signal).")
        }
        if let exitCode = Self.attribute("exit_code", of: event).flatMap(Int.init), exitCode != 0 {
            return Self.failure(
                event, title: "Sandbox execution failed", body: "\(name) exited with code \(exitCode).")
        }

        guard let startedAt else { return nil }
        let elapsed = event.timestamp.timeIntervalSince(startedAt)
        guard elapsed >= Self.minimumSuccessDuration else { return nil }
        return Self.success(
            event,
            title: "Sandbox execution finished",
            body: "\(name) finished in \(Self.formatted(elapsed))."
        )
    }

    /// One failure banner per sandbox. An execution that fails in a retry loop
    /// should leave its latest result on screen, not a stack of them.
    private static func failure(
        _ event: SandboxEventRecord, title: String, body: String
    ) -> AppNotification {
        notification(event, identifier: "sandbox.\(event.sandboxID).failure", title: title, body: body)
    }

    /// Distinct per event: two executions completing are two results, and the
    /// second must not silently replace the first.
    private static func success(
        _ event: SandboxEventRecord, title: String, body: String
    ) -> AppNotification {
        notification(
            event,
            identifier: "sandbox.\(event.sandboxID).finished.\(Int(event.timestamp.timeIntervalSince1970))",
            title: title,
            body: body
        )
    }

    private static func notification(
        _ event: SandboxEventRecord, identifier: String, title: String, body: String
    ) -> AppNotification {
        AppNotification(
            identifier: identifier,
            title: title,
            body: body,
            // A sandbox that no longer exists by the time the user clicks
            // resolves to the section plus an explanatory error, which is what
            // `resolveResourceDeepLink` is for.
            destination: .section(.sandboxes, id: event.sandboxID),
            category: .sandbox
        )
    }

    /// Attribute value, treating an empty string as absent.
    private static func attribute(_ key: String, of event: SandboxEventRecord) -> String? {
        guard let value = event.attributes[key], !value.isEmpty else { return nil }
        return value
    }

    /// Events carry no labels, so the short ID is the only name available —
    /// matching how `SandboxViewModel` falls back when a sandbox is unnamed.
    private static func name(of event: SandboxEventRecord) -> String {
        String(event.sandboxID.prefix(12))
    }

    private static func formatted(_ elapsed: TimeInterval) -> String {
        Duration.seconds(Int(elapsed))
            .formatted(.units(allowed: [.hours, .minutes, .seconds], width: .abbreviated))
    }
}
