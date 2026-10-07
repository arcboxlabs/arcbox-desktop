import ArcBoxClient

/// Keep an incident across reconnects. Only a current healthy observation ends the incident.
struct StorageNotificationRules {
    private var notifiedFailures: [RuntimeStorageVolume.Role: RuntimeStorageVolume.State] = [:]

    mutating func notification(
        for health: RuntimeStorageHealth?, isCurrent: Bool, isRuntimeReady: Bool
    ) -> AppNotification? {
        guard isCurrent, isRuntimeReady, let health else { return nil }
        var hasNewFailure = false
        for volume in health.volumes {
            if volume.state.preventsWrites {
                hasNewFailure = hasNewFailure || notifiedFailures[volume.role] != volume.state
                notifiedFailures[volume.role] = volume.state
            } else if volume.state == .mountedReadWrite || volume.state == .notConfigured {
                notifiedFailures.removeValue(forKey: volume.role)
            }
        }
        guard hasNewFailure, let message = health.writeFailureMessage else { return nil }
        return AppNotification(
            identifier: "runtime.storage",
            title: "Runtime storage needs attention",
            body: message,
            destination: .main,
            category: .daemonHealth
        )
    }
}
