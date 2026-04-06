import XCTest

@testable import ArcBox

@MainActor
final class ContainersViewModelTests: XCTestCase {

    private var vm: ContainersViewModel!

    override func setUp() {
        super.setUp()
        vm = ContainersViewModel()
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertTrue(vm.containers.isEmpty)
        XCTAssertNil(vm.selectedID)
        XCTAssertEqual(vm.runningCount, 0)
        XCTAssertEqual(vm.loadState, .waiting)
        XCTAssertNil(vm.lastError)
    }

    // MARK: - Selection

    func testSelectContainer() {
        vm.selectContainer("test-id")
        XCTAssertEqual(vm.selectedID, "test-id")
    }

    func testSelectContainerOverwritesPrevious() {
        vm.selectContainer("first")
        vm.selectContainer("second")
        XCTAssertEqual(vm.selectedID, "second")
    }

    func testSelectedContainerNilWhenNoMatch() {
        vm.selectContainer("nonexistent")
        XCTAssertNil(vm.selectedContainer)
    }

    func testSelectedContainerReturnsMatch() {
        let c = makeContainer(id: "c1", name: "nginx")
        vm.containers = [c]
        vm.selectContainer("c1")
        XCTAssertEqual(vm.selectedContainer?.id, "c1")
    }

    // MARK: - Group Toggling

    func testToggleGroupExpands() {
        XCTAssertFalse(vm.isGroupExpanded("project-a"))
        vm.toggleGroup("project-a")
        XCTAssertTrue(vm.isGroupExpanded("project-a"))
    }

    func testToggleGroupCollapses() {
        vm.toggleGroup("project-a")
        vm.toggleGroup("project-a")
        XCTAssertFalse(vm.isGroupExpanded("project-a"))
    }

    func testMultipleGroupsIndependent() {
        vm.toggleGroup("a")
        vm.toggleGroup("b")
        XCTAssertTrue(vm.isGroupExpanded("a"))
        XCTAssertTrue(vm.isGroupExpanded("b"))
        vm.toggleGroup("a")
        XCTAssertFalse(vm.isGroupExpanded("a"))
        XCTAssertTrue(vm.isGroupExpanded("b"))
    }

    // MARK: - Running Count

    func testRunningCountZeroWhenEmpty() {
        XCTAssertEqual(vm.runningCount, 0)
    }

    func testRunningCountReflectsState() {
        vm.containers = [
            makeContainer(id: "1", name: "a", state: .running),
            makeContainer(id: "2", name: "b", state: .stopped),
            makeContainer(id: "3", name: "c", state: .running),
        ]
        XCTAssertEqual(vm.runningCount, 2)
    }

    // MARK: - Search Filtering

    func testSearchEmptyReturnsAll() {
        vm.containers = [
            makeContainer(id: "1", name: "nginx"),
            makeContainer(id: "2", name: "redis"),
        ]
        vm.searchText = ""
        XCTAssertEqual(vm.standaloneContainers.count, 2)
    }

    func testSearchFiltersByName() {
        vm.containers = [
            makeContainer(id: "1", name: "nginx-web"),
            makeContainer(id: "2", name: "redis-cache"),
        ]
        vm.searchText = "nginx"
        XCTAssertEqual(vm.standaloneContainers.count, 1)
        XCTAssertEqual(vm.standaloneContainers.first?.name, "nginx-web")
    }

    func testSearchFiltersByImage() {
        vm.containers = [
            makeContainer(id: "1", name: "web", image: "nginx:latest"),
            makeContainer(id: "2", name: "cache", image: "redis:7"),
        ]
        vm.searchText = "redis"
        XCTAssertEqual(vm.standaloneContainers.count, 1)
        XCTAssertEqual(vm.standaloneContainers.first?.name, "cache")
    }

    func testSearchIsCaseInsensitive() {
        vm.containers = [
            makeContainer(id: "1", name: "NGINX")
        ]
        vm.searchText = "nginx"
        XCTAssertEqual(vm.standaloneContainers.count, 1)
    }

    // MARK: - Compose Groups

    func testComposeGroupsSeparated() {
        vm.containers = [
            makeContainer(id: "1", name: "web", composeProject: "myapp"),
            makeContainer(id: "2", name: "db", composeProject: "myapp"),
            makeContainer(id: "3", name: "standalone"),
        ]
        XCTAssertEqual(vm.composeGroups.count, 1)
        XCTAssertEqual(vm.composeGroups.first?.project, "myapp")
        XCTAssertEqual(vm.composeGroups.first?.containers.count, 2)
        XCTAssertEqual(vm.standaloneContainers.count, 1)
    }

    func testComposeGroupsFilteredBySearch() {
        vm.containers = [
            makeContainer(id: "1", name: "web", composeProject: "frontend"),
            makeContainer(id: "2", name: "api", composeProject: "backend"),
        ]
        vm.searchText = "web"
        XCTAssertEqual(vm.composeGroups.count, 1)
        XCTAssertEqual(vm.composeGroups.first?.project, "frontend")
    }

    func testSearchByComposeProject() {
        vm.containers = [
            makeContainer(id: "1", name: "svc", composeProject: "myproject")
        ]
        vm.searchText = "myproject"
        XCTAssertEqual(vm.composeGroups.count, 1)
    }

    // MARK: - DNS Domains

    func testHostDomainPlainContainer() {
        let c = makeContainer(id: "1", name: "nginx")
        XCTAssertEqual(c.hostDomain(useDNS: true), "nginx.arcbox.local")
        XCTAssertEqual(c.hostDomain(useDNS: false), "localhost")
    }

    func testHostDomainComposeContainer() {
        let c = makeContainer(
            id: "1", name: "myapp-web-1",
            composeProject: "myapp", composeService: "web"
        )
        XCTAssertEqual(c.hostDomain(useDNS: true), "web.myapp.arcbox.local")
        XCTAssertEqual(c.hostDomain(useDNS: false), "localhost")
    }

    func testAllDomainsPlainContainer() {
        let c = makeContainer(id: "1", name: "redis")
        let domains = c.allDomains(useDNS: true)
        XCTAssertEqual(domains, ["redis.arcbox.local"])
    }

    func testAllDomainsComposeContainer() {
        let c = makeContainer(
            id: "1", name: "myapp-web-1",
            composeProject: "myapp", composeService: "web"
        )
        let domains = c.allDomains(useDNS: true)
        XCTAssertEqual(
            domains,
            [
                "web.myapp.arcbox.local",
                "myapp-web-1.arcbox.local",
            ])
    }

    func testAllDomainsDNSDisabled() {
        let c = makeContainer(
            id: "1", name: "myapp-web-1",
            composeProject: "myapp", composeService: "web"
        )
        XCTAssertEqual(c.allDomains(useDNS: false), ["localhost"])
    }

    func testIsComposeFlag() {
        let plain = makeContainer(id: "1", name: "nginx")
        XCTAssertFalse(plain.isCompose)

        let compose = makeContainer(
            id: "2", name: "myapp-web-1",
            composeProject: "myapp", composeService: "web"
        )
        XCTAssertTrue(compose.isCompose)

        let partialProject = makeContainer(id: "3", name: "x", composeProject: "proj")
        XCTAssertFalse(partialProject.isCompose)

        let partialService = makeContainer(id: "4", name: "x", composeService: "svc")
        XCTAssertFalse(partialService.isCompose)
    }

    // MARK: - Last Error

    func testLastErrorClearing() {
        vm.lastError = "previous error"
        vm.selectContainer("x")
        XCTAssertEqual(vm.lastError, "previous error")
    }

    // MARK: - Helpers

    private func makeContainer(
        id: String,
        name: String,
        image: String = "nginx:latest",
        state: ContainerState = .stopped,
        composeProject: String? = nil,
        composeService: String? = nil
    ) -> ContainerViewModel {
        ContainerViewModel(
            id: id,
            name: name,
            image: image,
            state: state,
            ports: [],
            createdAt: Date(),
            composeProject: composeProject,
            composeService: composeService,
            labels: [:],
            cpuPercent: 0,
            memoryMB: 0,
            memoryLimitMB: 0
        )
    }
}
