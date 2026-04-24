import GRPCCore

/// Helpers for building gRPC metadata required by sandbox RPCs.
public enum SandboxMetadata {
    /// Build metadata containing the required `x-machine` header.
    ///
    /// All sandbox RPCs require this header to identify the target machine.
    /// Without it the server returns `INVALID_ARGUMENT`.
    public static func forMachine(_ machineID: String) -> Metadata {
        ["x-machine": .string(machineID)]
    }
}
