import Foundation

// MARK: - Common

public struct ObjectMeta: Codable, Sendable {
    public let name: String?
    public let namespace: String?
    public let uid: String?
    public let labels: [String: String]?
    public let creationTimestamp: Date?
}

public struct ListMeta: Codable, Sendable {
    public let resourceVersion: String?
}

// MARK: - Pods

public struct PodList: Codable, Sendable {
    public let metadata: ListMeta?
    public let items: [Pod]
}

public struct Pod: Codable, Sendable {
    public let metadata: ObjectMeta?
    public let spec: PodSpec?
    public let status: PodStatus?
}

public struct PodSpec: Codable, Sendable {
    public let nodeName: String?
    public let containers: [PodContainer]?
}

public struct PodContainer: Codable, Sendable {
    public let name: String?
    public let image: String?
}

public struct PodStatus: Codable, Sendable {
    public let phase: String?
    public let podIP: String?
    public let startTime: Date?
    public let containerStatuses: [ContainerStatus]?
}

public struct ContainerStatus: Codable, Sendable {
    public let name: String?
    public let ready: Bool?
    public let restartCount: Int?
    public let image: String?
    public let state: ContainerState?
}

public struct ContainerState: Codable, Sendable {
    public let running: ContainerStateRunning?
    public let waiting: ContainerStateWaiting?
    public let terminated: ContainerStateTerminated?
}

public struct ContainerStateRunning: Codable, Sendable {
    public let startedAt: Date?
}

public struct ContainerStateWaiting: Codable, Sendable {
    public let reason: String?
}

public struct ContainerStateTerminated: Codable, Sendable {
    public let exitCode: Int?
    public let reason: String?
}

// MARK: - Services

public struct ServiceList: Codable, Sendable {
    public let metadata: ListMeta?
    public let items: [K8sService]
}

/// Named `K8sService` to avoid collision with Foundation.
public struct K8sService: Codable, Sendable {
    public let metadata: ObjectMeta?
    public let spec: ServiceSpec?
}

public struct ServiceSpec: Codable, Sendable {
    public let type: String?
    public let clusterIP: String?
    public let ports: [ServicePort]?
    public let selector: [String: String]?
}

public struct ServicePort: Codable, Sendable {
    public let name: String?
    public let port: Int?
    public let targetPort: TargetPort?
    public let nodePort: Int?
    public let `protocol`: String?
}

/// targetPort can be an integer or a string in the K8s API.
public enum TargetPort: Codable, Sendable {
    case int(Int)
    case string(String)

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if let value = try? container.decode(Int.self) {
            self = .int(value)
        } else {
            self = .string(try container.decode(String.self))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .int(let value): try container.encode(value)
        case .string(let value): try container.encode(value)
        }
    }
}
