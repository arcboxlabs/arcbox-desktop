import XCTest
@testable import ArcBoxClient

@MainActor
final class ContainerRouteControllerTests: XCTestCase {
    func test_installRoutes_retriesUntilBridgeAppears() async {
        let spy = RouteSpy()
        var bridges = [nil, nil, "bridge107"]
        let sleepCounter = SleepCounter()
        let controller = ContainerRouteController(
            addRouteInterface: spy.add,
            removeRouteInterface: spy.remove,
            bridgeProvider: { bridges.removeFirst() },
            sleeper: { _ in sleepCounter.count += 1 }
        )

        await controller.installRoutes()

        XCTAssertEqual(spy.added, [.init(
            subnet: ContainerRouteController.containerSubnet,
            iface: "bridge107"
        )])
        XCTAssertEqual(controller.installedRouteInterface, "bridge107")
        XCTAssertEqual(sleepCounter.count, 2)
    }

    func test_installRoutes_retriesWhenRouteAddFails() async {
        let spy = RouteSpy(addFailuresRemaining: 2)
        let sleepCounter = SleepCounter()
        let controller = ContainerRouteController(
            addRouteInterface: spy.add,
            removeRouteInterface: spy.remove,
            bridgeProvider: { "bridge104" },
            sleeper: { _ in sleepCounter.count += 1 }
        )

        await controller.installRoutes()

        XCTAssertEqual(spy.added.count, 3)
        XCTAssertEqual(controller.installedRouteInterface, "bridge104")
        XCTAssertEqual(sleepCounter.count, 2)
    }

    func test_installRoutes_givesUpAfterMaxRetries() async {
        let spy = RouteSpy()
        let sleepCounter = SleepCounter()
        let controller = ContainerRouteController(
            addRouteInterface: spy.add,
            removeRouteInterface: spy.remove,
            bridgeProvider: { nil },
            sleeper: { _ in sleepCounter.count += 1 }
        )

        await controller.installRoutes()

        XCTAssertTrue(spy.added.isEmpty)
        XCTAssertNil(controller.installedRouteInterface)
        XCTAssertEqual(sleepCounter.count, ContainerRouteController.maxRouteRetries - 1)
    }

    func test_removeRoutes_removesInstalledRoute() async {
        let spy = RouteSpy()
        let controller = ContainerRouteController(
            addRouteInterface: spy.add,
            removeRouteInterface: spy.remove,
            bridgeProvider: { "bridge100" },
            sleeper: { _ in }
        )

        await controller.installRoutes()
        await controller.removeRoutes()

        XCTAssertEqual(spy.removed, [.init(
            subnet: ContainerRouteController.containerSubnet,
            iface: "bridge100"
        )])
        XCTAssertNil(controller.installedRouteInterface)
    }

    func test_removeRoutes_isNoOpWithoutInstalledRoute() async {
        let spy = RouteSpy()
        let controller = ContainerRouteController(
            addRouteInterface: spy.add,
            removeRouteInterface: spy.remove,
            bridgeProvider: { "bridge100" },
            sleeper: { _ in }
        )

        await controller.removeRoutes()

        XCTAssertTrue(spy.removed.isEmpty)
    }
}

@MainActor
private final class RouteSpy {
    struct RouteCall: Equatable {
        let subnet: String
        let iface: String
    }

    enum TestError: Error {
        case addFailed
        case removeFailed
    }

    private(set) var added: [RouteCall] = []
    private(set) var removed: [RouteCall] = []
    private var addFailuresRemaining: Int
    private let removeError: Error?

    init(addFailuresRemaining: Int = 0, removeError: Error? = nil) {
        self.addFailuresRemaining = addFailuresRemaining
        self.removeError = removeError
    }

    func add(subnet: String, iface: String) async throws {
        added.append(.init(subnet: subnet, iface: iface))
        if addFailuresRemaining > 0 {
            addFailuresRemaining -= 1
            throw TestError.addFailed
        }
    }

    func remove(subnet: String, iface: String) async throws {
        removed.append(.init(subnet: subnet, iface: iface))
        if let removeError {
            throw removeError
        }
    }
}

private final class SleepCounter {
    var count = 0
}
