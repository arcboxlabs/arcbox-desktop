import Foundation

/// Open-source notices shipped in `Contents/Resources/ThirdPartyNotices`.
///
/// `components.json` is maintained by hand in the repository and lists the
/// binaries ArcBox redistributes. The DMG packager adds `generated.json`
/// (Swift packages and the runtime's Rust crates) and the license files it
/// references, so a development build shows only the hand-maintained groups.
nonisolated struct ThirdPartyNotices: Sendable {
    static let manifestNames = ["components.json", "generated.json"]

    let directory: URL
    let groups: [ThirdPartyNoticeGroup]

    static var bundled: URL? {
        Bundle.main.resourceURL?.appendingPathComponent("ThirdPartyNotices", isDirectory: true)
    }

    /// Reads every manifest present in `directory`, in `manifestNames` order.
    /// `components.json` is required; `generated.json` exists only in packaged builds.
    static func load(from directory: URL) throws -> ThirdPartyNotices {
        var groups: [ThirdPartyNoticeGroup] = []
        for name in manifestNames {
            let url = directory.appendingPathComponent(name)
            guard name == manifestNames[0] || FileManager.default.fileExists(atPath: url.path) else { continue }
            let manifest = try JSONDecoder().decode(Manifest.self, from: Data(contentsOf: url))
            for var group in manifest.groups {
                for index in group.components.indices {
                    group.components[index].id = "\(group.id)/\(index)"
                }
                groups.append(group)
            }
        }
        return ThirdPartyNotices(directory: directory, groups: groups)
    }

    /// The component's license files, concatenated under a heading each.
    @concurrent
    static func licenseText(of component: ThirdPartyNoticeComponent, in directory: URL) async -> String {
        component.licenseFiles.map { path in
            let text =
                (try? String(contentsOf: directory.appendingPathComponent(path), encoding: .utf8))
                ?? "This license file is missing from this copy of ArcBox."
            return "==> \(path) <==\n\n\(text)"
        }
        .joined(separator: "\n\n")
    }

    nonisolated private struct Manifest: Decodable {
        let groups: [ThirdPartyNoticeGroup]
    }
}

nonisolated struct ThirdPartyNoticeGroup: Identifiable, Sendable, Decodable {
    let id: String
    let title: String
    let summary: String?
    let location: String?
    var components: [ThirdPartyNoticeComponent]
}

nonisolated struct ThirdPartyNoticeComponent: Identifiable, Sendable, Decodable {
    /// `<group id>/<index>`, assigned by `load`: names repeat across groups
    /// (the GNU C Library is linked into binaries from two different builds).
    var id = ""
    let name: String
    let version: String
    let license: String
    let source: URL?
    let licenseFiles: [String]
    let notes: String?

    private enum CodingKeys: String, CodingKey {
        case name, version, license, source, licenseFiles, notes
    }
}
