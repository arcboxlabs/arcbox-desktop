import ArcBoxClient
import XCTest

@testable import ArcBox

@MainActor
final class MachineModelTests: XCTestCase {

    // MARK: - State parsing

    func testStateParsesDaemonWireStrings() {
        XCTAssertEqual(MachineState(apiState: "created"), .created)
        XCTAssertEqual(MachineState(apiState: "starting"), .starting)
        XCTAssertEqual(MachineState(apiState: "running"), .running)
        XCTAssertEqual(MachineState(apiState: "stopping"), .stopping)
        XCTAssertEqual(MachineState(apiState: "stopped"), .stopped)
    }

    func testUnknownStateFallsBackToStopped() {
        XCTAssertEqual(MachineState(apiState: "hibernating"), .stopped)
        XCTAssertEqual(MachineState(apiState: ""), .stopped)
    }

    // MARK: - Summary mapping

    private func makeSummary() -> Arcbox_V1_MachineSummary {
        var summary = Arcbox_V1_MachineSummary()
        summary.id = "dev"
        summary.name = "dev"
        summary.state = "running"
        summary.cpus = 4
        summary.memory = 4 << 30
        summary.diskSize = 50 << 30
        summary.ipAddress = "192.168.66.2"
        summary.created = 1_700_000_000
        summary.distro = "ubuntu"
        summary.distroVersion = "noble"
        return summary
    }

    func testViewModelFromSummary() {
        let vm = MachineViewModel(from: makeSummary())
        XCTAssertEqual(vm.id, "dev")
        XCTAssertEqual(vm.state, .running)
        XCTAssertEqual(vm.cpuCores, 4)
        XCTAssertEqual(vm.memoryGB, 4)
        XCTAssertEqual(vm.diskGB, 50)
        XCTAssertEqual(vm.ipAddress, "192.168.66.2")
        XCTAssertEqual(vm.distro.name, "ubuntu")
        XCTAssertEqual(vm.distro.version, "noble")
        XCTAssertEqual(vm.distro.displayName, "Ubuntu")
        XCTAssertEqual(vm.createdAt, Date(timeIntervalSince1970: 1_700_000_000))
    }

    func testEmptyIPBecomesNil() {
        var summary = makeSummary()
        summary.ipAddress = ""
        XCTAssertNil(MachineViewModel(from: summary).ipAddress)
    }

    func testEmptyDistroDisplaysAsLinux() {
        var summary = makeSummary()
        summary.distro = ""
        summary.distroVersion = ""
        XCTAssertEqual(MachineViewModel(from: summary).distro.displayName, "Linux")
    }

    func testByteSizesRoundToNearestGB() {
        var summary = makeSummary()
        // 4096 MiB - 512 MiB rounds down; + 512 MiB rounds up.
        summary.memory = (4 << 30) - (1 << 29) - 1
        summary.diskSize = (50 << 30) + (1 << 29)
        let vm = MachineViewModel(from: summary)
        XCTAssertEqual(vm.memoryGB, 3)
        XCTAssertEqual(vm.diskGB, 51)
    }

    // MARK: - Detail merge

    func testApplyDetailsAndPreserveAcrossRefresh() {
        var vm = MachineViewModel(from: makeSummary())

        var info = Arcbox_V1_MachineInfo()
        info.hardware.arch = "aarch64"
        info.network.gateway = "10.0.2.1"
        info.network.macAddress = "aa:bb:cc:dd:ee:ff"
        info.network.dnsServers = ["1.1.1.1"]
        var mount = Arcbox_V1_DirectoryMount()
        mount.hostPath = "/Users/me/src"
        mount.guestPath = "/src"
        mount.readonly = true
        info.mounts = [mount]
        info.startedAt.seconds = 1_700_000_100
        vm.applyDetails(from: info)

        XCTAssertEqual(vm.architecture, "aarch64")
        XCTAssertEqual(vm.gateway, "10.0.2.1")
        XCTAssertEqual(vm.dnsServers, ["1.1.1.1"])
        XCTAssertEqual(vm.mounts.first?.guestPath, "/src")
        XCTAssertEqual(vm.mounts.first?.readOnly, true)
        XCTAssertEqual(vm.startedAt, Date(timeIntervalSince1970: 1_700_000_100))

        // A list refresh rebuilds from the summary; details must survive.
        var refreshed = MachineViewModel(from: makeSummary())
        refreshed.preserveDetailFrom(vm)
        XCTAssertEqual(refreshed.architecture, "aarch64")
        XCTAssertEqual(refreshed.gateway, "10.0.2.1")
        XCTAssertEqual(refreshed.mounts.count, 1)
        XCTAssertEqual(refreshed.startedAt, vm.startedAt)
    }
}
