import Foundation
import OSLog
@preconcurrency import Sentry

extension DaemonManager {
    // MARK: - gRPC Setup Status Stream

    /// Connect to the daemon's `WatchSetupStatus` gRPC stream and drive
    /// state updates from the stream. When the stream connects, the daemon
    /// is alive. When it disconnects, the daemon died.
    ///
    /// This replaces the old `/_ping` polling approach.
    @available(macOS 15.0, *)
    public func connectAndWatch(client: ArcBoxClient) {
        stopWatching()
        reconnectCount = 0
        lastMessageTime = nil
        watchTask = Task { [weak self] in
            // Track consecutive failed reconnect attempts since the last
            // successful stream message.  Used to keep .running state for a
            // short grace period on transient disconnects so the UI doesn't
            // flash "Starting ArcBox Daemon..." for a brief stream hiccup.
            var failedAttemptsSinceLastMessage = 0

            // Retry loop: reconnect on stream disconnect.
            while !Task.isCancelled {
                // Get a fresh service reference each iteration so we pick up
                // any transport recovery in ArcBoxClient (its internal
                // GRPCClient is swapped after runConnections() terminates).
                let systemService = client.system

                // Bridge: gRPC Sendable closure writes into the stream,
                // MainActor-isolated code reads from it.
                let (stream, continuation) = AsyncStream<Arcbox_V1_SetupStatus>.makeStream()

                let rpcTask = Task.detached {
                    do {
                        try await systemService.watchSetupStatus(
                            request: .init(message: .init())
                        ) { response in
                            for try await message in response.messages {
                                continuation.yield(message)
                            }
                        }
                    } catch {
                        ClientLog.daemon.warning(
                            "WatchSetupStatus stream error: \(error.localizedDescription, privacy: .private)")
                    }
                    continuation.finish()
                }

                for await message in stream {
                    guard !Task.isCancelled else { break }
                    failedAttemptsSinceLastMessage = 0
                    self?.applySetupStatusSync(message)
                }

                rpcTask.cancel()

                guard !Task.isCancelled else { return }

                // Stream ended — daemon may have restarted.
                //
                // If we were previously .running, DON'T immediately regress
                // to .registered.  Transient gRPC disconnects (daemon GC
                // pause, socket buffer pressure, HTTP/2 GOAWAY) are normal
                // and the reconnect loop usually recovers within one cycle.
                // Immediately showing the loading UI for these is jarring.
                //
                // Grace window: ~3 s (6 attempts × 500 ms backoff).  After
                // that, the daemon is genuinely unreachable and the UI should
                // reflect it.
                failedAttemptsSinceLastMessage += 1
                self?.reconnectCount += 1
                let graceExceeded = failedAttemptsSinceLastMessage > 6

                // Emit Sentry breadcrumb on stream reconnect for crash debugging.
                SentrySDK.addBreadcrumb(
                    {
                        let b = Breadcrumb(
                            level: graceExceeded ? .error : .warning,
                            category: "grpc.stream")
                        b.message =
                            "reconnect #\(failedAttemptsSinceLastMessage)"
                        return b
                    }())

                if self?.state.isRunning != true || graceExceeded {
                    self?.state = .registered
                    self?.setupPhase = .unknown
                    if graceExceeded {
                        ClientLog.daemon.warning(
                            "Daemon unreachable after \(failedAttemptsSinceLastMessage) reconnect attempts, state → .registered"
                        )
                    }
                }

                // Back off before reconnecting.
                try? await Task.sleep(for: .milliseconds(500))
            }
        }
    }

    /// Stop watching the gRPC stream.
    public func stopWatching() {
        watchTask?.cancel()
        watchTask = nil
    }

    // MARK: - Internal

    /// Apply a setup status update. Called from MainActor-isolated stream handlers.
    private func applySetupStatusSync(_ status: Arcbox_V1_SetupStatus) {
        let oldPhase = setupPhase
        lastMessageTime = Date()

        dnsResolverInstalled = status.dnsResolverInstalled
        dockerSocketLinked = status.dockerSocketLinked
        routeInstalled = status.routeInstalled
        vmRunning = status.vmRunning
        dockerToolsInstalled = status.dockerToolsInstalled
        setupMessage = status.message

        switch status.phase {
        case .unspecified: setupPhase = .unknown
        case .initializing: setupPhase = .initializing
        case .downloadingAssets: setupPhase = .downloadingAssets
        case .assetsReady: setupPhase = .assetsReady
        case .vmStarting: setupPhase = .vmStarting
        case .vmReady: setupPhase = .vmReady
        case .networkReady: setupPhase = .networkReady
        case .ready: setupPhase = .ready
        case .degraded: setupPhase = .degraded
        case .cleaningUp: setupPhase = .cleaningUp
        case .UNRECOGNIZED: setupPhase = .unknown
        }

        // Emit a Sentry breadcrumb on phase transitions for crash debugging.
        if setupPhase != oldPhase {
            let crumb = Breadcrumb(level: .info, category: "daemon.phase")
            crumb.message = "\(oldPhase) → \(setupPhase)"
            SentrySDK.addBreadcrumb(crumb)
        }

        // Any message from the stream means the daemon is alive.
        if state != .running {
            state = .running
            ClientLog.daemon.info("Daemon is running (gRPC stream connected)")
        }
    }
}
