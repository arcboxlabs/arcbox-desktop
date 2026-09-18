import Foundation
import Yams

extension KubeConfig {
    // MARK: - Private

    static func parseKubeConfigDocument(from yaml: String) throws -> KubeConfigDocument {
        try YAMLDecoder().decode(KubeConfigDocument.self, from: yaml)
    }

    /// Decode every PEM block in `data` to DER, in order; never empty.
    ///
    /// Blocks are decoded one at a time because each carries its own base64 padding: k3s
    /// ships `client-certificate-data` as a chain (the leaf, then the CA that signed it),
    /// and a CA bundle may hold several roots. Data without PEM armor is already DER.
    static func derBlocks(_ data: Data) throws -> [Data] {
        guard let pem = String(data: data, encoding: .utf8),
            pem.contains("-----BEGIN")
        else {
            return [data]
        }

        var blocks: [Data] = []
        var body: String?
        for line in pem.components(separatedBy: .newlines).map({ $0.trimmingCharacters(in: .whitespaces) }) {
            if line.hasPrefix("-----BEGIN") {
                body = ""
            } else if line.hasPrefix("-----END") {
                guard let encoded = body, let der = Data(base64Encoded: encoded) else {
                    throw KubeConfigError.invalidCertificate("Malformed PEM block")
                }
                blocks.append(der)
                body = nil
            } else {
                body?.append(line)
            }
        }
        guard body == nil, !blocks.isEmpty else {
            throw KubeConfigError.invalidCertificate("Unterminated PEM block")
        }
        return blocks
    }
}

struct KubeConfigDocument: Decodable {
    let currentContext: String?
    let clusters: [NamedCluster]
    let contexts: [NamedContext]?
    let users: [NamedUser]

    enum CodingKeys: String, CodingKey {
        case currentContext = "current-context"
        case clusters
        case contexts
        case users
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        currentContext = try container.decodeIfPresent(String.self, forKey: .currentContext)
        clusters = try container.decodeIfPresent([NamedCluster].self, forKey: .clusters) ?? []
        contexts = try container.decodeIfPresent([NamedContext].self, forKey: .contexts)
        users = try container.decodeIfPresent([NamedUser].self, forKey: .users) ?? []
    }
}

struct NamedCluster: Decodable {
    let name: String
    let cluster: Cluster
}

struct Cluster: Decodable {
    let server: String?
    let certificateAuthorityData: String?

    enum CodingKeys: String, CodingKey {
        case server
        case certificateAuthorityData = "certificate-authority-data"
    }
}

struct NamedContext: Decodable {
    let name: String
    let context: Context
}

struct Context: Decodable {
    let cluster: String
    let user: String
}

struct NamedUser: Decodable {
    let name: String
    let user: User
}

struct User: Decodable {
    let clientCertificateData: String?
    let clientKeyData: String?
    let exec: ExecConfig?

    enum CodingKeys: String, CodingKey {
        case clientCertificateData = "client-certificate-data"
        case clientKeyData = "client-key-data"
        case exec
    }
}
