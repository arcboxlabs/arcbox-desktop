import Foundation
import Yams

extension KubeConfig {
    // MARK: - Private

    static func parseKubeConfigDocument(from yaml: String) throws -> KubeConfigDocument {
        try YAMLDecoder().decode(KubeConfigDocument.self, from: yaml)
    }

    /// Convert PEM-encoded data to DER by stripping headers and decoding inner base64.
    /// If the data is already DER (no PEM headers), returns it as-is.
    static func pemToDER(_ data: Data) -> Data {
        guard let pem = String(data: data, encoding: .utf8),
            pem.contains("-----BEGIN")
        else {
            return data
        }
        let base64 =
            pem
            .components(separatedBy: .newlines)
            .filter { !$0.hasPrefix("-----") }
            .joined()
        return Data(base64Encoded: base64) ?? data
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
    }

    struct NamedCluster: Decodable {
        let name: String
        let cluster: Cluster
    }

    struct Cluster: Decodable {
        let server: String
        let certificateAuthorityData: String

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

}
