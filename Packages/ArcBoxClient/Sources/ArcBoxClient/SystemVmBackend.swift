/// Hypervisor backend for the System VM, mirroring the proto `SystemVmBackend`.
public enum SystemVmBackend: String, CaseIterable, Identifiable, Sendable {
    /// Virtualization.framework — Apple-managed execution. The default; runs amd64 via Rosetta.
    case vz
    /// Hypervisor.framework — ArcBox's custom VMM. Runs amd64 via FEX.
    case hv
    /// QEMU TCG — software emulation for Macs without hardware virtualization, such as
    /// macOS virtual machines. Much slower. Runs amd64 via FEX.
    case qemu

    public var id: String { rawValue }

    /// Display name of the underlying technology.
    public var label: String {
        switch self {
        case .vz: "Virtualization.framework"
        case .hv: "Hypervisor.framework"
        case .qemu: "Software emulation (slower)"
        }
    }

    /// Whether the backend needs a Mac with hardware virtualization.
    public var requiresHardwareVirtualization: Bool {
        self != .qemu
    }

    /// Creates a backend from its wire value; `nil` for unspecified or unknown values.
    public init?(proto: Arcbox_V1_SystemVmBackend) {
        switch proto {
        case .vz: self = .vz
        case .hv: self = .hv
        case .qemu: self = .qemu
        case .unspecified, .UNRECOGNIZED: return nil
        }
    }

    /// The wire value for this backend.
    public var proto: Arcbox_V1_SystemVmBackend {
        switch self {
        case .vz: .vz
        case .hv: .hv
        case .qemu: .qemu
        }
    }
}
