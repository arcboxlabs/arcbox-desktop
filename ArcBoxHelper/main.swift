import Foundation
import OSLog
@preconcurrency import Sentry
import ServiceManagement

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    /// Bundle ID of the main app. Hardcoded — matches PRODUCT_BUNDLE_IDENTIFIER in pbxproj.
    private static let appBundleID = "com.arcboxlabs.desktop"

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        // Validate caller using audit token (tamper-proof, unlike PID checks).
        // Team ID comes from the helper's own Info.plist (ArcBoxHelperInfo.plist),
        // where $(DEVELOPMENT_TEAM) is expanded by Xcode at build time.
        guard let teamID = Bundle.main.object(forInfoDictionaryKey: "ArcBoxTeamID") as? String,
              !teamID.isEmpty
        else {
            HelperLog.xpc.error("Missing ArcBoxTeamID in Info.plist")
            return false
        }

        do {
            // Allow any binary signed by the same team (app + helperctl + daemon).
            // Previously restricted to appBundleID only, which blocked helperctl.
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

HelperLog.xpc.info("ArcBoxHelper starting (protocol v\(kArcBoxHelperProtocolVersion, privacy: .public))")

// Initialize Sentry for the helper process (no UI features).
if let dsn = Bundle.main.object(forInfoDictionaryKey: "SentryDSN") as? String,
   !dsn.isEmpty, dsn != "YOUR_SENTRY_DSN_HERE", dsn != "$(SENTRY_DSN)"
{
    SentrySDK.start { options in
        options.dsn = dsn
        options.enableCrashHandler = true
        options.enableAutoSessionTracking = false
        options.enableAutoPerformanceTracing = false
        // attachScreenshot is unavailable in macOS command-line tools.
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

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: "com.arcboxlabs.desktop.helper")
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
