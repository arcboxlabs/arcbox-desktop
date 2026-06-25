import Foundation

@available(macOS 15.0, *)
public struct ContainerInspectMountSnapshot: Sendable {
    public let type: String?
    public let source: String?
    public let destination: String?
    public let rw: Bool?

    public init(type: String?, source: String?, destination: String?, rw: Bool?) {
        self.type = type
        self.source = source
        self.destination = destination
        self.rw = rw
    }
}

@available(macOS 15.0, *)
public struct ContainerInspectSnapshot: Sendable {
    public let domainname: String?
    public let ipAddress: String?
    public let mounts: [ContainerInspectMountSnapshot]
    public let rootfsMountPath: String?

    public init(
        domainname: String?,
        ipAddress: String?,
        mounts: [ContainerInspectMountSnapshot],
        rootfsMountPath: String? = nil
    ) {
        self.domainname = domainname
        self.ipAddress = ipAddress
        self.mounts = mounts
        self.rootfsMountPath = rootfsMountPath
    }
}

@available(macOS 15.0, *)
public struct ImageInspectSnapshot: Sendable {
    public let labels: [String: String]
    public let rootfsMountPath: String?

    public init(labels: [String: String], rootfsMountPath: String? = nil) {
        self.labels = labels
        self.rootfsMountPath = rootfsMountPath
    }
}

@available(macOS 15.0, *)
public enum DockerClientError: Error, Sendable {
    case invalidHTTPStatus(Int)
    case invalidResponseBody
    case invalidJSON
}

/// A single line from Docker container logs.
@available(macOS 15.0, *)
public struct DockerLogLine: Sendable {
    public enum Stream: Sendable {
        case stdout
        case stderr
    }

    public let stream: Stream
    public let message: String
    public let timestamp: String?

    public init(stream: Stream, message: String, timestamp: String? = nil) {
        self.stream = stream
        self.message = message
        self.timestamp = timestamp
    }
}
