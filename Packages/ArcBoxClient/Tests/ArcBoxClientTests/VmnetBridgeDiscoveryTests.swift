import XCTest
@testable import ArcBoxClient

final class VmnetBridgeDiscoveryTests: XCTestCase {
    func test_parseBridgeInterface_returnsBridgeWithVmenetMember() {
        let output = """
        lo0: flags=8049<UP,LOOPBACK,RUNNING,MULTICAST> mtu 16384
        en0: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
        bridge105: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
        \tmember: vmenet0 flags=3<LEARNING,DISCOVER>
        \tid 00:00:00:00:00:00 priority 0 hellotime 0 fwddelay 0
        """

        XCTAssertEqual(
            VmnetBridgeDiscovery.parseBridgeInterface(fromIfconfigOutput: output),
            "bridge105"
        )
    }

    func test_parseBridgeInterface_returnsNilWithoutVmnetMember() {
        let output = """
        bridge100: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
        \tmember: en7 flags=3<LEARNING,DISCOVER>
        """

        XCTAssertNil(VmnetBridgeDiscovery.parseBridgeInterface(fromIfconfigOutput: output))
    }

    func test_parseBridgeInterface_returnsFirstVmnetBridgeWhenMultipleExist() {
        let output = """
        bridge101: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
        \tmember: vmenet1 flags=3<LEARNING,DISCOVER>
        bridge107: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
        \tmember: vmenet2 flags=3<LEARNING,DISCOVER>
        """

        XCTAssertEqual(
            VmnetBridgeDiscovery.parseBridgeInterface(fromIfconfigOutput: output),
            "bridge101"
        )
    }

    func test_parseBridgeInterface_prefersBridgeMatchingTargetMACAddress() {
        let output = """
        bridge101: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
        \tmember: vmenet1 flags=3<LEARNING,DISCOVER>
        bridge107: flags=8863<UP,BROADCAST,SMART,RUNNING,SIMPLEX,MULTICAST> mtu 1500
        \tmember: vmenet2 flags=3<LEARNING,DISCOVER>
        vmenet1: flags=8943<UP,BROADCAST,RUNNING,PROMISC,SIMPLEX,MULTICAST> mtu 1500
        \tether 02:11:22:33:44:55
        vmenet2: flags=8943<UP,BROADCAST,RUNNING,PROMISC,SIMPLEX,MULTICAST> mtu 1500
        \tether 02:aa:bb:cc:dd:ee
        """

        XCTAssertEqual(
            VmnetBridgeDiscovery.parseBridgeInterface(
                fromIfconfigOutput: output,
                targetMACAddress: "02-AA-BB-CC-DD-EE"
            ),
            "bridge107"
        )
    }

    func test_fallbackBridgeInterface_returnsFirstExistingBridge() {
        let bridge = VmnetBridgeDiscovery.fallbackBridgeInterface { name in
            name == "bridge103" || name == "bridge108"
        }

        XCTAssertEqual(bridge, "bridge103")
    }
}
