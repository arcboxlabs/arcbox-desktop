/// ArcBoxHelper — Privileged helper with two modes:
///
/// 1. **Daemon mode** (default): XPC listener for app and helperctl calls.
///    Started by launchd as a LaunchDaemon.
///
/// 2. **CLI mode** (`route` subcommand): Thin XPC client for daemon to call.
///    Usage: ArcBoxHelper route {ensure|remove|status} [--subnet ...] [--bridge-mac ...]
///    Output: JSON to stdout. Exit code 0 = success, 1 = error.

import Foundation
import OSLog
@preconcurrency import Sentry
import ServiceManagement

// ─── Mode dispatch ──────────────────────────────────────────────────────────

if CommandLine.arguments.count >= 2 && CommandLine.arguments[1] == "route" {
    runCLI()
    // Never reached — runCLI calls exit().
} else {
    runDaemon()
    // Never reached — runDaemon enters RunLoop.
}

// ─── Daemon mode (XPC listener) ─────────────────────────────────────────────

func runDaemon() -> Never {
    HelperLog.xpc.info("ArcBoxHelper starting in daemon mode (protocol v\(kArcBoxHelperProtocolVersion, privacy: .public))")

    initSentry()

    let delegate = HelperDelegate()
    let listener = NSXPCListener(machServiceName: "com.arcboxlabs.desktop.helper")
    listener.delegate = delegate
    listener.resume()
    RunLoop.main.run()
    fatalError("RunLoop exited unexpectedly")
}

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        guard let teamID = Bundle.main.object(forInfoDictionaryKey: "ArcBoxTeamID") as? String,
              !teamID.isEmpty
        else {
            HelperLog.xpc.error("Missing ArcBoxTeamID in Info.plist")
            return false
        }

        do {
            // Allow any binary signed by the same team (app, daemon, or self as CLI).
            try connection.setCodeSigningRequirement(
                "anchor apple generic and " +
                "certificate leaf[subject.OU] = \"\(teamID)\""
            )
        } catch {
            HelperLog.xpc.error("Code signing requirement failed: \(error.localizedDescription, privacy: .public)")
            return false
        }

        connection.exportedInterface = NSXPCInterface(with: ArcBoxHelperProtocol.self)
        connection.exportedObject = HelperOperations()
        connection.resume()
        HelperLog.xpc.info("Accepted XPC connection")
        return true
    }
}

// ─── CLI mode (XPC client) ──────────────────────────────────────────────────

func runCLI() -> Never {
    let args = CommandLine.arguments

    guard args.count >= 3 else {
        fputs("Usage: ArcBoxHelper route {ensure|remove|status} [--subnet ...] [--bridge-mac ...]\n", stderr)
        exit(1)
    }

    let subcommand = args[2]

    func arg(_ name: String) -> String? {
        guard let idx = args.firstIndex(of: name), idx + 1 < args.count else { return nil }
        return args[idx + 1]
    }

    let subnet = arg("--subnet") ?? "172.16.0.0/12"

    // Connect to ourselves running as XPC daemon.
    let conn = NSXPCConnection(machServiceName: "com.arcboxlabs.desktop.helper", options: .privileged)
    conn.remoteObjectInterface = NSXPCInterface(with: ArcBoxHelperProtocol.self)
    conn.resume()

    let sem = DispatchSemaphore(value: 0)
    var exitCode: Int32 = 0

    guard let proxy = conn.remoteObjectProxyWithErrorHandler({ error in
        fputs("{\"ok\":false,\"error\":\"\(error.localizedDescription)\"}\n", stderr)
        exitCode = 1
        sem.signal()
    }) as? ArcBoxHelperProtocol else {
        fputs("{\"ok\":false,\"error\":\"failed to create XPC proxy\"}\n", stderr)
        exit(1)
    }

    switch subcommand {
    case "ensure":
        guard let mac = arg("--bridge-mac") else {
            fputs("{\"ok\":false,\"error\":\"--bridge-mac required\"}\n", stderr)
            exit(1)
        }
        proxy.ensureRoute(subnet: subnet, bridgeMac: mac) { json, error in
            if let error {
                print("{\"ok\":false,\"error\":\"\(error.localizedDescription)\"}")
                exitCode = 1
            } else if let json {
                print(json)
            } else {
                print("{\"ok\":false,\"error\":\"no response\"}")
                exitCode = 1
            }
            sem.signal()
        }

    case "remove":
        proxy.removeRoute(subnet: subnet) { error in
            if let error {
                print("{\"ok\":false,\"error\":\"\(error.localizedDescription)\"}")
                exitCode = 1
            } else {
                print("{\"ok\":true}")
            }
            sem.signal()
        }

    case "status":
        proxy.routeStatus(subnet: subnet) { json in
            print(json ?? "{\"installed\":false}")
            sem.signal()
        }

    default:
        fputs("Unknown subcommand: \(subcommand)\n", stderr)
        exit(1)
    }

    sem.wait()
    conn.invalidate()
    exit(exitCode)
}

// ─── Sentry ─────────────────────────────────────────────────────────────────

func initSentry() {
    guard let dsn = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String,
          !dsn.isEmpty, dsn != "YOUR_SENTRY_DSN_HERE", dsn != "$(SENTRY_DSN)"
    else { return }

    SentrySDK.start { options in
        options.dsn = dsn
        options.enableCrashHandler = true
        options.enableAutoSessionTracking = false
        options.enableAutoPerformanceTracing = false
        options.tracesSampleRate = 0
        #if DEBUG
        options.debug = true
        options.environment = "development"
        #else
        options.environment = "production"
        #endif
    }
    SentrySDK.configureScope { scope in
        scope.setTag(value: "helper", key: "process_type")
    }
    HelperLog.xpc.info("Sentry initialized for helper")
}
