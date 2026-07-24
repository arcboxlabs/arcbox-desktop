import Darwin
import Foundation

/// Local hardware facts available before this Mac enrolls in a Fleet.
enum RunnerHostCapability {
    static var chipName: String {
        var size = 0
        guard sysctlbyname("machdep.cpu.brand_string", nil, &size, nil, 0) == 0, size > 0 else {
            return "Apple Silicon"
        }
        var brand = [CChar](repeating: 0, count: size)
        guard sysctlbyname("machdep.cpu.brand_string", &brand, &size, nil, 0) == 0 else {
            return "Apple Silicon"
        }
        let bytes = brand.prefix(while: { $0 != 0 }).map { UInt8(bitPattern: $0) }
        return String(bytes: bytes, encoding: .utf8) ?? "Apple Silicon"
    }
}
