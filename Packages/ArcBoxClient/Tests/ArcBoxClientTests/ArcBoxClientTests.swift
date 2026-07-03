import ArcBoxClient
import Testing

@Suite struct SystemVmBackendTests {
    /// Pins the wire mapping — a consistent swap in both directions would
    /// still pass a pure round-trip test.
    @Test func wireValues() {
        #expect(SystemVmBackend.vz.proto == Arcbox_V1_SystemVmBackend.vz)
        #expect(SystemVmBackend.hv.proto == Arcbox_V1_SystemVmBackend.hv)
    }

    @Test func protoRoundTrip() {
        for backend in SystemVmBackend.allCases {
            #expect(SystemVmBackend(proto: backend.proto) == backend)
        }
    }

    @Test func unknownWireValuesMapToNil() {
        #expect(SystemVmBackend(proto: .unspecified) == nil)
        #expect(SystemVmBackend(proto: .UNRECOGNIZED(99)) == nil)
    }
}
