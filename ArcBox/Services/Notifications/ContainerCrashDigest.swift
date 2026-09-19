import Foundation

/// Renders a batch of container deaths as one notification.
enum ContainerCrashDigest {
    /// Names listed in full before the body switches to a count.
    private static let namesShown = 3

    /// One rolling identifier: the latest digest is the current state of
    /// things, and should replace whatever it superseded.
    private static let identifier = "container.crashes"

    static func notification(for crashes: [ContainerCrash]) -> AppNotification? {
        // A container that died several times inside one window is one story.
        var seen = Set<String>()
        let unique = crashes.filter { seen.insert($0.containerID).inserted }

        guard let first = unique.first else { return nil }

        if unique.count == 1 {
            return AppNotification(
                identifier: identifier,
                title: "Container exited",
                body: "\(first.name) exited with code \(first.exitCode).",
                destination: .section(.containers, id: first.containerID),
                category: .container
            )
        }

        let shown = unique.prefix(namesShown)
        let names = shown.map(\.name).joined(separator: ", ")
        let remainder = unique.count - shown.count
        return AppNotification(
            identifier: identifier,
            title: "\(unique.count) containers exited",
            body: remainder > 0 ? "\(names) and \(remainder) more." : "\(names).",
            // No single container to select, so this lands on the list.
            destination: .section(.containers, id: nil),
            category: .container
        )
    }
}
