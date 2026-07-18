import CryptoKit
import Foundation

/// Layer chain IDs per the OCI image spec.
///
/// The containerd image store keys committed layer snapshots by chain ID:
/// the first chain ID is the first diff ID, and each following one is
/// `sha256("<previous chain ID> <diff ID>")`. The daemon resolves an
/// image's layer directories from the top (last) chain ID.
enum ImageLayerChain {
    /// Chain ID of the top layer for `diffIDs` (bottom-most first, as
    /// reported by `RootFS.Layers`), or `nil` when there are no layers.
    /// Pure computation — nonisolated so callers off the main actor (tests,
    /// background resolution) can use it directly.
    nonisolated static func topChainID(diffIDs: [String]) -> String? {
        guard var chain = diffIDs.first else { return nil }
        for diff in diffIDs.dropFirst() {
            let digest = SHA256.hash(data: Data("\(chain) \(diff)".utf8))
            chain = "sha256:" + digest.map { String(format: "%02x", $0) }.joined()
        }
        return chain
    }
}
