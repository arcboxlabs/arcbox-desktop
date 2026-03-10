import Foundation
import ServiceManagement

final class HelperDelegate: NSObject, NSXPCListenerDelegate {
    /// Bundle ID of the main app. Hardcoded — matches PRODUCT_BUNDLE_IDENTIFIER in pbxproj.
    private static let appBundleID = "com.arcbox.arcbox-desktop-swift"

    func listener(
        _ listener: NSXPCListener,
        shouldAcceptNewConnection connection: NSXPCConnection
    ) -> Bool {
        // Validate caller using audit token (tamper-proof, unlike PID checks).
        // Team ID comes from the helper's own Info.plist (ArcBoxHelperInfo.plist),
        // where $(DEVELOPMENT_TEAM) is expanded by Xcode at build time.
        guard let teamID = Bundle.main.object(forInfoDictionaryKey: "ArcBoxTeamID") as? String,
              !teamID.isEmpty
        else { return false }

        do {
            try connection.setCodeSigningRequirement(
                "anchor apple generic and " +
                "certificate leaf[subject.OU] = \"\(teamID)\" and " +
                "identifier \"\(Self.appBundleID)\""
            )
        } catch {
            return false
        }

        connection.exportedInterface = NSXPCInterface(with: ArcBoxHelperProtocol.self)
        connection.exportedObject = HelperOperations()
        connection.resume()
        return true
    }
}

let delegate = HelperDelegate()
let listener = NSXPCListener(machServiceName: "io.arcbox.desktop.helper")
listener.delegate = delegate
listener.resume()
RunLoop.main.run()
