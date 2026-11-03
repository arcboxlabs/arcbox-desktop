import Foundation

/// What the daemon bundled with this app can do.
///
/// The app and its daemon ship together, pinned by `arcbox.version`, which the app carries
/// as a resource. That answers capability questions before the daemon is registered or
/// reachable — in particular whether a Mac without hardware virtualization may start it.
public enum EmbeddedRuntime {
    /// The first arcbox release whose daemon boots the System VM under QEMU software
    /// emulation on a Mac without hardware virtualization. From it on, startup no longer
    /// turns such Macs away (see `StartupOrchestrator`), and Settings offers the backend.
    ///
    /// v0.11.0 had the QEMU backend but not this: the System VM failed in rcS without the
    /// vhost-user device backends and the DIC=0 QEMU build, and with `[qemu]`
    /// `arch.arm64.sha256` empty in `assets.lock` the daemon never downloaded QEMU.
    /// v0.11.1 has both and pins the published QEMU v0.1.0 build.
    static let softwareEmulationMinimumVersion = Version("v0.11.1")

    /// The `arcbox.version` bundled with the app; `nil` when it is missing or unreadable.
    public static let bundledVersion: String? = Bundle.main
        .url(forResource: "arcbox", withExtension: "version")
        .flatMap { try? String(contentsOf: $0, encoding: .utf8) }
        .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }

    /// Whether the bundled daemon can run the System VM without hardware virtualization.
    public static var supportsSoftwareEmulation: Bool {
        supportsSoftwareEmulation(bundledVersion: bundledVersion, minimum: softwareEmulationMinimumVersion)
    }

    static func supportsSoftwareEmulation(bundledVersion: String?, minimum: Version?) -> Bool {
        guard let minimum, let bundled = bundledVersion.flatMap(Version.init) else { return false }
        return bundled >= minimum
    }

    /// An arcbox release tag, `vMAJOR.MINOR.PATCH`.
    struct Version: Comparable {
        let components: [Int]

        init?(_ tag: String) {
            let parts = tag.drop(while: { $0 == "v" }).split(separator: ".", omittingEmptySubsequences: false)
            let numbers = parts.compactMap { Int($0) }
            guard parts.count == 3, numbers.count == 3 else { return nil }
            components = numbers
        }

        static func < (lhs: Version, rhs: Version) -> Bool {
            lhs.components.lexicographicallyPrecedes(rhs.components)
        }
    }
}
