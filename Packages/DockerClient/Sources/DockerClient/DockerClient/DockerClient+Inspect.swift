import AsyncHTTPClient
import Foundation

extension DockerClient {
    /// Raw inspect fallback that bypasses generated date decoding.
    ///
    /// Docker sometimes returns date fields that fail strict OpenAPI decoding.
    /// This method parses only the fields we need from raw JSON.
    public func inspectContainerSnapshot(id: String) async throws -> ContainerInspectSnapshot {
        let data = try await rawInspectData(path: "/containers/\(id)/json")
        do {
            return try JSONDecoder().decode(ContainerInspectDTO.self, from: data).snapshot
        } catch is DecodingError {
            throw DockerClientError.invalidJSON
        }
    }

    /// Raw image inspect fallback that bypasses generated date decoding.
    /// Parses only fields used by UI.
    public func inspectImageSnapshot(id: String) async throws -> ImageInspectSnapshot {
        let data = try await rawInspectData(path: "/images/\(id)/json")
        do {
            return try JSONDecoder().decode(ImageInspectDTO.self, from: data).snapshot
        } catch is DecodingError {
            throw DockerClientError.invalidJSON
        }
    }

    private func rawInspectData(path inspectPath: String) async throws -> Data {
        let encodedSocket =
            socketPath
            .addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? socketPath
        let encodedPath =
            inspectPath.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? inspectPath
        let path = Self.defaultServerURL.path + encodedPath
        let urlString = "http+unix://\(encodedSocket)\(path)"

        var request = HTTPClientRequest(url: urlString)
        request.method = .GET
        request.headers.add(name: "Accept", value: "application/json")

        let response = try await httpClient.execute(request, timeout: timeout)
        guard (200..<300).contains(response.status.code) else {
            throw DockerClientError.invalidHTTPStatus(Int(response.status.code))
        }

        var data = Data()
        for try await var chunk in response.body {
            if let bytes = chunk.readBytes(length: chunk.readableBytes) {
                data.append(contentsOf: bytes)
            }
        }

        return data
    }

    fileprivate static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

}

private struct ContainerInspectDTO: Decodable {
    let config: ContainerConfigDTO?
    let networkSettings: ContainerNetworkSettingsDTO?
    let mounts: [ContainerMountDTO]
    let graphDriver: GraphDriverDTO?

    var snapshot: ContainerInspectSnapshot {
        ContainerInspectSnapshot(
            domainname: DockerClient.normalized(config?.domainname),
            ipAddress: networkSettings?.ipAddress,
            mounts: mounts.map(\.snapshot),
            rootfsMountPath: graphDriver?.containerRootfsMountPath
        )
    }

    private enum CodingKeys: String, CodingKey {
        case config = "Config"
        case networkSettings = "NetworkSettings"
        case mounts = "Mounts"
        case graphDriver = "GraphDriver"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        config = try? container.decodeIfPresent(ContainerConfigDTO.self, forKey: .config)
        networkSettings = try? container.decodeIfPresent(
            ContainerNetworkSettingsDTO.self,
            forKey: .networkSettings
        )
        mounts = (try? container.decodeIfPresent([ContainerMountDTO].self, forKey: .mounts)) ?? []
        graphDriver = try? container.decodeIfPresent(GraphDriverDTO.self, forKey: .graphDriver)
    }
}

private struct ImageInspectDTO: Decodable {
    let config: ImageConfigDTO?
    let containerConfig: ImageConfigDTO?
    let graphDriver: GraphDriverDTO?

    var snapshot: ImageInspectSnapshot {
        ImageInspectSnapshot(
            labels: config?.normalizedLabels ?? containerConfig?.normalizedLabels ?? [:],
            rootfsMountPath: graphDriver?.imageRootfsMountPath
        )
    }

    private enum CodingKeys: String, CodingKey {
        case config = "Config"
        case containerConfig = "ContainerConfig"
        case graphDriver = "GraphDriver"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        config = try? container.decodeIfPresent(ImageConfigDTO.self, forKey: .config)
        containerConfig = try? container.decodeIfPresent(ImageConfigDTO.self, forKey: .containerConfig)
        graphDriver = try? container.decodeIfPresent(GraphDriverDTO.self, forKey: .graphDriver)
    }
}

private struct ContainerConfigDTO: Decodable {
    let domainname: String?

    private enum CodingKeys: String, CodingKey {
        case domainname = "Domainname"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        domainname = try? container.decodeIfPresent(String.self, forKey: .domainname)
    }
}

private struct ImageConfigDTO: Decodable {
    let labels: StringMapDTO?

    var normalizedLabels: [String: String]? {
        labels?.values
    }

    private enum CodingKeys: String, CodingKey {
        case labels = "Labels"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        labels = try? container.decodeIfPresent(StringMapDTO.self, forKey: .labels)
    }
}

private struct ContainerNetworkSettingsDTO: Decodable {
    let primaryIPAddress: String?
    let networks: [String: NetworkEndpointDTO]?

    var ipAddress: String? {
        DockerClient.normalized(primaryIPAddress)
            ?? networks?.values.lazy.compactMap { DockerClient.normalized($0.ipAddress) }.first
    }

    private enum CodingKeys: String, CodingKey {
        case primaryIPAddress = "IPAddress"
        case networks = "Networks"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        primaryIPAddress = try? container.decodeIfPresent(String.self, forKey: .primaryIPAddress)
        networks = try? container.decodeIfPresent(
            [String: NetworkEndpointDTO].self,
            forKey: .networks
        )
    }
}

private struct NetworkEndpointDTO: Decodable {
    let ipAddress: String?

    private enum CodingKeys: String, CodingKey {
        case ipAddress = "IPAddress"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        ipAddress = try? container.decodeIfPresent(String.self, forKey: .ipAddress)
    }
}

private struct ContainerMountDTO: Decodable {
    let type: String?
    let source: String?
    let destination: String?
    let rw: Bool?

    var snapshot: ContainerInspectMountSnapshot {
        ContainerInspectMountSnapshot(
            type: DockerClient.normalized(type),
            source: DockerClient.normalized(source),
            destination: DockerClient.normalized(destination),
            rw: rw
        )
    }

    private enum CodingKeys: String, CodingKey {
        case type = "Type"
        case source = "Source"
        case destination = "Destination"
        case rw = "RW"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        type = try? container.decodeIfPresent(String.self, forKey: .type)
        source = try? container.decodeIfPresent(String.self, forKey: .source)
        destination = try? container.decodeIfPresent(String.self, forKey: .destination)
        rw = try? container.decodeIfPresent(Bool.self, forKey: .rw)
    }
}

private struct GraphDriverDTO: Decodable {
    let data: GraphDriverDataDTO?

    var containerRootfsMountPath: String? {
        DockerClient.normalized(data?.mergedDir) ?? DockerClient.normalized(data?.upperDir)
    }

    var imageRootfsMountPath: String? {
        containerRootfsMountPath ?? DockerClient.normalized(data?.dir)
    }

    private enum CodingKeys: String, CodingKey {
        case data = "Data"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        data = try? container.decodeIfPresent(GraphDriverDataDTO.self, forKey: .data)
    }
}

private struct GraphDriverDataDTO: Decodable {
    let mergedDir: String?
    let upperDir: String?
    let dir: String?

    private enum CodingKeys: String, CodingKey {
        case mergedDir = "MergedDir"
        case upperDir = "UpperDir"
        case dir = "Dir"
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        mergedDir = try? container.decodeIfPresent(String.self, forKey: .mergedDir)
        upperDir = try? container.decodeIfPresent(String.self, forKey: .upperDir)
        dir = try? container.decodeIfPresent(String.self, forKey: .dir)
    }
}

private struct StringMapDTO: Decodable {
    let values: [String: String]

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: DynamicCodingKey.self)
        var values: [String: String] = [:]
        values.reserveCapacity(container.allKeys.count)
        for key in container.allKeys {
            guard let value = try? container.decode(String.self, forKey: key),
                let normalizedValue = DockerClient.normalized(value)
            else { continue }
            values[key.stringValue] = normalizedValue
        }
        self.values = values
    }
}

private struct DynamicCodingKey: CodingKey {
    let stringValue: String
    let intValue: Int?

    init?(stringValue: String) {
        self.stringValue = stringValue
        intValue = nil
    }

    init?(intValue: Int) {
        stringValue = String(intValue)
        self.intValue = intValue
    }
}
