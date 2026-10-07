import Foundation

public struct RuntimeStorageVolume: Sendable, Equatable {
    public enum Role: Sendable, Hashable {
        case data
        case metadata
        case unknown(Int)

        public var label: String {
            switch self {
            case .data: "Data"
            case .metadata: "Metadata"
            case .unknown(let value): "Unknown volume (\(value))"
            }
        }
    }

    public enum State: Sendable, Equatable {
        case mountedReadWrite
        case readOnly
        case unavailable
        case notConfigured
        case unknown(Int)

        public var label: String {
            switch self {
            case .mountedReadWrite: "Mounted read-write"
            case .readOnly: "Read-only"
            case .unavailable: "Unavailable"
            case .notConfigured: "Not configured"
            case .unknown: "Unknown"
            }
        }

        public var preventsWrites: Bool {
            self == .readOnly || self == .unavailable
        }
    }

    public let role: Role
    public let state: State
    public let device: String
    public let mountPoint: String
    public let filesystem: String
    public let detail: String

    init(_ volume: Arcbox_V1_StorageVolumeHealth) {
        role =
            switch volume.role {
            case .data: .data
            case .metadata: .metadata
            case .unspecified: .unknown(0)
            case .UNRECOGNIZED(let value): .unknown(value)
            }
        state =
            switch volume.state {
            case .mountedReadWrite: .mountedReadWrite
            case .readOnly: .readOnly
            case .unavailable: .unavailable
            case .notConfigured: .notConfigured
            case .unspecified: .unknown(0)
            case .UNRECOGNIZED(let value): .unknown(value)
            }
        device = volume.device
        mountPoint = volume.mountPoint
        filesystem = volume.filesystem
        detail = volume.detail
    }
}

/// A guest mount observation. Read-write mounting does not prove durable writes succeed.
public struct RuntimeStorageHealth: Sendable, Equatable {
    public let volumes: [RuntimeStorageVolume]
    public let observedAt: Date?

    public init(_ health: Arcbox_V1_StorageHealth) {
        volumes = health.volumes.map(RuntimeStorageVolume.init)
        observedAt =
            health.observedAtUnixMs == 0
            ? nil
            : Date(
                timeIntervalSince1970: Double(health.observedAtUnixMs) / 1000)
    }

    public var affectedVolumes: [RuntimeStorageVolume] {
        volumes.filter { $0.state.preventsWrites }
    }

    public var writeFailureMessage: String? {
        let affected = affectedVolumes
        guard !affected.isEmpty else { return nil }
        let summary = affected.map { "\($0.role.label): \($0.state.label.lowercased())" }.joined(separator: "; ")
        return
            "Runtime storage cannot accept writes (\(summary)). Open Settings > Storage for diagnostics and recovery."
    }
}
