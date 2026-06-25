import AsyncHTTPClient
import Foundation

extension DockerClient {
    /// Raw inspect fallback that bypasses generated date decoding.
    ///
    /// Docker sometimes returns date fields that fail strict OpenAPI decoding.
    /// This method parses only the fields we need from raw JSON.
    public func inspectContainerSnapshot(id: String) async throws -> ContainerInspectSnapshot {
        let encodedSocket =
            socketPath
            .addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? socketPath
        let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let path = Self.defaultServerURL.path + "/containers/\(encodedID)/json"
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

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DockerClientError.invalidJSON
        }

        let config = json["Config"] as? [String: Any]
        let domainname = Self.normalized(config?["Domainname"] as? String)

        let networkSettings = json["NetworkSettings"] as? [String: Any]
        let primaryIP = Self.normalized(networkSettings?["IPAddress"] as? String)
        var ipAddress = primaryIP
        if ipAddress == nil,
            let networks = networkSettings?["Networks"] as? [String: Any]
        {
            for value in networks.values {
                guard let endpoint = value as? [String: Any] else { continue }
                if let ip = Self.normalized(endpoint["IPAddress"] as? String) {
                    ipAddress = ip
                    break
                }
            }
        }

        let mountsArray = json["Mounts"] as? [[String: Any]] ?? []
        let mounts = mountsArray.map { mount in
            ContainerInspectMountSnapshot(
                type: Self.normalized(mount["Type"] as? String),
                source: Self.normalized(mount["Source"] as? String),
                destination: Self.normalized(mount["Destination"] as? String),
                rw: mount["RW"] as? Bool
            )
        }

        let graphDriver = json["GraphDriver"] as? [String: Any]
        let graphDriverData = graphDriver?["Data"] as? [String: Any]
        let rootfsMountPath =
            Self.normalized(graphDriverData?["MergedDir"] as? String)
            ?? Self.normalized(graphDriverData?["UpperDir"] as? String)

        return ContainerInspectSnapshot(
            domainname: domainname,
            ipAddress: ipAddress,
            mounts: mounts,
            rootfsMountPath: rootfsMountPath
        )
    }

    /// Raw image inspect fallback that bypasses generated date decoding.
    /// Parses only fields used by UI.
    public func inspectImageSnapshot(id: String) async throws -> ImageInspectSnapshot {
        let encodedSocket =
            socketPath
            .addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? socketPath
        let encodedID = id.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? id
        let path = Self.defaultServerURL.path + "/images/\(encodedID)/json"
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

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw DockerClientError.invalidJSON
        }

        let config = json["Config"] as? [String: Any]
        let containerConfig = json["ContainerConfig"] as? [String: Any]
        let labels =
            Self.extractStringMap(config?["Labels"])
            ?? Self.extractStringMap(containerConfig?["Labels"])
            ?? [:]

        let graphDriver = json["GraphDriver"] as? [String: Any]
        let graphDriverData = graphDriver?["Data"] as? [String: Any]
        let rootfsMountPath =
            Self.normalized(graphDriverData?["MergedDir"] as? String)
            ?? Self.normalized(graphDriverData?["UpperDir"] as? String)
            ?? Self.normalized(graphDriverData?["Dir"] as? String)

        return ImageInspectSnapshot(
            labels: labels,
            rootfsMountPath: rootfsMountPath
        )
    }

    private static func normalized(_ value: String?) -> String? {
        guard let value else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func extractStringMap(_ value: Any?) -> [String: String]? {
        guard let raw = value as? [String: Any] else { return nil }
        var normalizedMap: [String: String] = [:]
        normalizedMap.reserveCapacity(raw.count)
        for (key, val) in raw {
            if let stringValue = normalized(val as? String) {
                normalizedMap[key] = stringValue
            }
        }
        return normalizedMap
    }
}
