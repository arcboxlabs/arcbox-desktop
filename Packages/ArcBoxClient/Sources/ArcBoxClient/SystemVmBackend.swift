/// Hypervisor backend for the System VM, mirroring the proto `SystemVmBackend`.
public enum SystemVmBackend: String, CaseIterable, Identifiable, Sendable {
    /// Virtualization.framework — Apple-managed execution. The default; runs amd64 via Rosetta.
    case vz
    /// Hypervisor.framework — ArcBox's custom VMM. Runs amd64 via FEX.
    case hv

    public var id: String { rawValue }

    /// Display name of the underlying technology.
    public var label: String {
        switch self {
        case .vz: "Virtualization.framework"
        case .hv: "Hypervisor.framework"
        }
    }

    /// Creates a backend from its wire value; `nil` for unspecified or unknown values.
    public init?(proto: Arcbox_V1_SystemVmBackend) {
        switch proto {
        case .vz: self = .vz
        case .hv: self = .hv
        case .unspecified, .UNRECOGNIZED: return nil
        }
    }

    /// The wire value for this backend.
    public var proto: Arcbox_V1_SystemVmBackend {
        switch self {
        case .vz: .vz
        case .hv: .hv
        }
    }
}
