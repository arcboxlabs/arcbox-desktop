import DockerClient
import Foundation

/// A container that died on its own.
struct ContainerCrash: Equatable {
    let containerID: String
    let name: String
    let exitCode: Int
}

/// Decides which container deaths are worth interrupting the user for.
///
/// Exit codes alone cannot answer this: `docker stop` produces the same
/// `die`/`exitCode=137` a killed container does. What separates them is that
/// Docker announces an intentional exit first — the observed sequence for
/// `docker stop` is `kill` (SIGTERM), `kill` (SIGKILL), `stop`, then `die`.
struct ContainerNotificationRules {
    /// How long the same container stays quiet after being announced. A
    /// container under `restart: always` with a broken image dies every few
    /// seconds forever; the first report is news and the rest are not.
    static let repeatCooldown: TimeInterval = 300

    /// How long a `kill` or `stop` explains a death.
    ///
    /// A container that traps SIGTERM and keeps running would otherwise leave
    /// intent sitting there forever, silently swallowing the next genuine
    /// crash. A signal that does end a container ends it within milliseconds,
    /// and a long `docker stop -t N` is covered regardless because Docker emits
    /// `stop` immediately before the `die` — so this window only has to be
    /// longer than a kill takes, not longer than a grace period.
    static let intentWindow: TimeInterval = 10

    /// The signals that ask a container to end, as Linux numbers: the daemon
    /// writes `strconv.Itoa(int(signal))` into the event regardless of the name
    /// the caller used.
    ///
    /// `docker kill` delivers whatever it is given, and most of what people
    /// send that way is addressed to a container expected to keep running —
    /// SIGHUP to reload configuration, SIGUSR1 for something the application
    /// defines. Those explain no death.
    ///
    /// An image's own `STOPSIGNAL` is deliberately absent (httpd's is SIGWINCH)
    /// and does not need to be here: `docker stop` announces `stop` before the
    /// `die` whichever signal it sent.
    private static let terminationSignals: Set<Int> = [
        2,  // SIGINT
        3,  // SIGQUIT
        9,  // SIGKILL
        15,  // SIGTERM
    ]

    /// Containers whose imminent exit the user asked for, and when they asked.
    private var intentionalExits: [String: Date] = [:]
    /// When each container was last announced, to apply `repeatCooldown`.
    private var lastAnnounced: [String: Date] = [:]

    mutating func crash(for event: DockerClient.DockerEvent) -> ContainerCrash? {
        guard event.type == "container", let id = event.actorID else { return nil }

        switch event.action {
        case "kill":
            if asksToTerminate(event) {
                intentionalExits[id] = event.date
            }
            return nil

        case "stop":
            intentionalExits[id] = event.date
            return nil

        case "die":
            return death(of: id, event: event)

        case "start":
            // A restart is a fresh life: whatever was asked of the previous
            // one no longer explains the next exit.
            intentionalExits.removeValue(forKey: id)
            return nil

        case "destroy":
            intentionalExits.removeValue(forKey: id)
            lastAnnounced.removeValue(forKey: id)
            return nil

        // Everything else, including `exec_die` — health check probes emit
        // that with a non-zero exit code every few seconds on a container
        // whose probe is failing, and it says nothing about the container
        // itself.
        default:
            return nil
        }
    }

    // MARK: - Private

    /// Whether a `kill` asked the container to end.
    ///
    /// A signal that cannot be read is taken as a termination request, which
    /// keeps a stop quiet rather than announcing it as a crash.
    private func asksToTerminate(_ event: DockerClient.DockerEvent) -> Bool {
        guard let signal = event.attributes["signal"].flatMap(Int.init) else { return true }
        return Self.terminationSignals.contains(signal)
    }

    private mutating func death(of id: String, event: DockerClient.DockerEvent) -> ContainerCrash? {
        // Consume the intent either way: it explains exactly one death, and a
        // stale one explains nothing.
        let intent = intentionalExits.removeValue(forKey: id)
        if let intent, event.date.timeIntervalSince(intent) <= Self.intentWindow {
            return nil
        }

        guard let exitCode = event.attributes["exitCode"].flatMap(Int.init), exitCode != 0 else {
            return nil
        }
        if let announced = lastAnnounced[id],
            event.date.timeIntervalSince(announced) < Self.repeatCooldown
        {
            return nil
        }
        lastAnnounced[id] = event.date

        return ContainerCrash(
            containerID: id,
            name: event.attributes["name"] ?? String(id.prefix(12)),
            exitCode: exitCode
        )
    }
}
