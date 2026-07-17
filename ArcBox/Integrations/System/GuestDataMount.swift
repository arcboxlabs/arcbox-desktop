import Foundation

/// Maps guest data paths to their host location under `~/ArcBox`.
///
/// The ArcBox daemon exports the guest's docker data root (`/var/lib/docker`)
/// read-only over NFSv4 and mounts it at `~/ArcBox`; the containerd data root
/// (`/var/lib/containerd`, where the containerd image store keeps every
/// snapshot) rides along as a child export at `~/ArcBox/containerd`. Guest
/// paths — volume mountpoints, image/container layer directories — are
/// browsed on the host via a prefix rewrite:
/// `/var/lib/docker/<rest>` → `~/ArcBox/<rest>` and
/// `/var/lib/containerd/<rest>` → `~/ArcBox/containerd/<rest>`.
enum GuestDataMount {
    /// Guest docker data root the export corresponds to.
    /// Mirrors `DOCKER_DATA_MOUNT_POINT` in the runtime.
    static let guestDataRoot = "/var/lib/docker"

    /// Guest containerd data root, exported as a child of the docker export.
    /// Mirrors `CONTAINERD_DATA_MOUNT_POINT` in the runtime.
    static let guestContainerdRoot = "/var/lib/containerd"

    /// Host mount point of the read-only guest data export.
    static var rootURL: URL {
        FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("ArcBox")
    }

    /// Whether the guest data export is currently mounted at `~/ArcBox`.
    static var isMounted: Bool {
        var isDirectory: ObjCBool = false
        return FileManager.default.fileExists(atPath: rootURL.path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// Rewrites a guest path under one of the exported roots to its host URL
    /// under `~/ArcBox`, or `nil` if the path is not within an exported root.
    ///
    /// Guest paths can come from image/container labels, i.e. untrusted input;
    /// any `.`/`..` component is rejected so a crafted label cannot escape the
    /// export once the URL is standardized downstream.
    static func hostURL(forGuestPath guestPath: String) -> URL? {
        let trimmed = guestPath.trimmingCharacters(in: .whitespacesAndNewlines)
        // Check containerd first: its prefix is not nested inside the docker
        // root, but keeping the more specific mapping first stays correct if
        // that ever changes.
        if let url = rewrite(trimmed, root: guestContainerdRoot, to: containerdHostRoot) {
            return url
        }
        return rewrite(trimmed, root: guestDataRoot, to: rootURL)
    }

    /// Host location of the containerd child export.
    private static var containerdHostRoot: URL {
        rootURL.appendingPathComponent("containerd")
    }

    private static func rewrite(_ path: String, root: String, to hostRoot: URL) -> URL? {
        guard path == root || path.hasPrefix(root + "/") else {
            return nil
        }
        let relative =
            path
            .dropFirst(root.count)
            .trimmingCharacters(in: CharacterSet(charactersIn: "/"))
        guard !relative.split(separator: "/").contains(where: { $0 == ".." || $0 == "." }) else {
            return nil
        }
        return relative.isEmpty ? hostRoot : hostRoot.appendingPathComponent(relative)
    }

    /// A user-facing explanation for why a translated path could not be browsed.
    ///
    /// Distinguishes "the export isn't mounted at all" from "the export is
    /// mounted but this particular path isn't in it" (e.g. a running
    /// container's overlay filesystem, which is a live submount not carried by
    /// the read-only bind).
    static func unavailableMessage(subject: String) -> String {
        if isMounted {
            return "\(subject) isn't present in the ~/ArcBox export."
        }
        return "Guest data isn't mounted at ~/ArcBox. Ensure the ArcBox daemon is running."
    }
}
