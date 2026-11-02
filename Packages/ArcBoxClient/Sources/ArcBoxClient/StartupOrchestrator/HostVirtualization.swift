import Darwin
import Virtualization

/// Whether this Mac can boot the daemon's runtime VM.
///
/// A Mac that is itself a virtual machine reports neither signal: macOS guests get no
/// nested virtualization, so the daemon's VM start fails with "Virtualization.framework
/// not available". Turning away a Mac that could virtualize is the costly mistake, so
/// either signal is enough.
@MainActor
public enum HostVirtualization {
    public static var isAvailable: Bool {
        hypervisorSupported || VZVirtualMachine.isSupported
    }

    /// `kern.hv_support` is absent, not zero, inside a macOS virtual machine.
    private static var hypervisorSupported: Bool {
        var value: Int32 = 0
        var size = MemoryLayout<Int32>.size
        return sysctlbyname("kern.hv_support", &value, &size, nil, 0) == 0 && value == 1
    }
}
