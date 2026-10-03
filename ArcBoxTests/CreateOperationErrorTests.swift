import DockerClient
import XCTest

@testable import ArcBox

/// Create and pull operations used to return `nil`/`false` on failure without touching
/// `lastError`, so the error toast either stayed silent or showed the previous operation's
/// message. Each one must now clear `lastError` on entry and populate it on every failure path.
@MainActor
final class CreateOperationErrorTests: XCTestCase {

    private var containerOptions: ContainerCreateOptions {
        ContainerCreateOptions(
            image: "alpine:latest",
            name: "",
            platform: nil,
            command: "",
            entrypoint: "",
            workingDir: "",
            autoRemove: false,
            restartPolicy: "no",
            privileged: false,
            readOnlyRootfs: false,
            dockerInit: false
        )
    }

    // MARK: - Failures are reported

    func testCreateContainerReportsFailure() async {
        let vm = ContainersViewModel()
        let id = await vm.createContainer(options: containerOptions, docker: nil)
        XCTAssertNil(id)
        XCTAssertNotNil(vm.lastError)
    }

    func testPullImageReportsFailure() async {
        let vm = ImagesViewModel()
        let ok = await vm.pullImage("alpine:latest", platform: nil, docker: nil)
        XCTAssertFalse(ok)
        XCTAssertNotNil(vm.lastError)
    }

    func testCreateVolumeReportsFailure() async {
        let vm = VolumesViewModel()
        let ok = await vm.createVolume(name: "data", docker: nil)
        XCTAssertFalse(ok)
        XCTAssertNotNil(vm.lastError)
    }

    func testCreateNetworkReportsFailure() async {
        let vm = NetworksViewModel()
        let ok = await vm.createNetwork(name: "bridge-1", enableIPv6: false, docker: nil)
        XCTAssertFalse(ok)
        XCTAssertNotNil(vm.lastError)
    }

    func testImportVolumeReportsFailure() async {
        let vm = VolumesViewModel()
        let ok = await vm.importVolume(
            name: "data", tarURL: URL(fileURLWithPath: "/nonexistent.tar"), docker: nil)
        XCTAssertFalse(ok)
        XCTAssertNotNil(vm.lastError)
    }

    func testImportImageReportsFailure() async {
        let vm = ImagesViewModel()
        let ok = await vm.importImage(tarURL: URL(fileURLWithPath: "/nonexistent.tar"), docker: nil)
        XCTAssertFalse(ok)
        XCTAssertNotNil(vm.lastError)
    }

    func testCreateNetworkRejectsBlankName() async {
        let vm = NetworksViewModel()
        let ok = await vm.createNetwork(name: "   ", enableIPv6: false, docker: nil)
        XCTAssertFalse(ok)
        XCTAssertEqual(vm.lastError, "Network name is required.")
    }

    // MARK: - Stale errors are cleared

    /// The reported symptom: the toast showed a message left over from an earlier action.
    func testCreateNetworkReplacesAStaleError() async {
        let vm = NetworksViewModel()
        vm.lastError = "left over from a previous delete"
        _ = await vm.createNetwork(name: "   ", enableIPv6: false, docker: nil)
        XCTAssertEqual(vm.lastError, "Network name is required.")
    }

    func testCreateContainerDoesNotKeepAStaleError() async {
        let vm = ContainersViewModel()
        vm.lastError = "left over from a previous stop"
        _ = await vm.createContainer(options: containerOptions, docker: nil)
        XCTAssertNotEqual(vm.lastError, "left over from a previous stop")
    }

    func testPullImageDoesNotKeepAStaleError() async {
        let vm = ImagesViewModel()
        vm.lastError = "left over from a previous remove"
        _ = await vm.pullImage("alpine:latest", platform: nil, docker: nil)
        XCTAssertNotEqual(vm.lastError, "left over from a previous remove")
    }

    func testCreateVolumeDoesNotKeepAStaleError() async {
        let vm = VolumesViewModel()
        vm.lastError = "left over from a previous delete"
        _ = await vm.createVolume(name: "data", docker: nil)
        XCTAssertNotEqual(vm.lastError, "left over from a previous delete")
    }
}

@MainActor
final class ResourceDeletionTests: XCTestCase {
    func testAttachedImageAndNetworkAreRejectedBeforeDocker() async {
        let imageViewModel = ImagesViewModel()
        imageViewModel.images = [
            ImageViewModel(
                id: "image",
                dockerId: "sha256:image",
                repository: "postgres",
                tag: "18",
                sizeBytes: 0,
                createdAt: nil,
                inUse: true,
                os: "linux",
                architecture: "arm64"
            )
        ]
        imageViewModel.selectedID = "image"
        await imageViewModel.removeImage("image", dockerId: "sha256:image", docker: nil)
        XCTAssertEqual(imageViewModel.selectedID, "image")
        XCTAssertEqual(imageViewModel.lastError, "Image is in use and cannot be deleted.")

        let networkViewModel = NetworksViewModel()
        networkViewModel.networks = [
            NetworkViewModel(
                id: "network",
                name: "project_default",
                driver: "bridge",
                scope: "local",
                createdAt: .distantPast,
                internal: false,
                attachable: false,
                containerCount: 1
            )
        ]
        networkViewModel.selectedID = "network"
        await networkViewModel.removeNetwork("network", docker: nil)
        XCTAssertEqual(networkViewModel.selectedID, "network")
        XCTAssertEqual(networkViewModel.lastError, "Network is in use and cannot be deleted.")
    }

    func testImageFailuresPreserveSelectionAndExposeDockerReason() {
        let viewModel = ImagesViewModel()
        viewModel.selectedID = "image"

        let inUse = Operations.ImageDelete.Output.conflict(
            .init(body: .json(.init(message: "image is referenced by a container")))
        )
        XCTAssertFalse(viewModel.applyImageDeletion(inUse, id: "image"))
        XCTAssertEqual(viewModel.selectedID, "image")
        XCTAssertEqual(viewModel.lastError, "image is referenced by a container")

        let generic = Operations.ImageDelete.Output.internalServerError(
            .init(body: .json(.init(message: "snapshotter failed")))
        )
        XCTAssertFalse(viewModel.applyImageDeletion(generic, id: "image"))
        XCTAssertEqual(viewModel.selectedID, "image")
        XCTAssertEqual(viewModel.lastError, "snapshotter failed")
    }

    func testVolumeFailuresPreserveSelectionAndExposeDockerReason() {
        let viewModel = VolumesViewModel()
        viewModel.selectedID = "data"

        let inUse = Operations.VolumeDelete.Output.conflict(
            .init(body: .json(.init(message: "volume is in use")))
        )
        XCTAssertFalse(viewModel.applyVolumeDeletion(inUse, name: "data"))
        XCTAssertEqual(viewModel.selectedID, "data")
        XCTAssertEqual(viewModel.lastError, "volume is in use")

        let generic = Operations.VolumeDelete.Output.internalServerError(
            .init(body: .json(.init(message: "storage driver failed")))
        )
        XCTAssertFalse(viewModel.applyVolumeDeletion(generic, name: "data"))
        XCTAssertEqual(viewModel.selectedID, "data")
        XCTAssertEqual(viewModel.lastError, "storage driver failed")

        XCTAssertTrue(viewModel.applyVolumeDeletion(.noContent, name: "data"))
        XCTAssertNil(viewModel.selectedID)
    }

    func testNetworkFailuresPreserveSelectionAndExposeDockerReason() {
        let viewModel = NetworksViewModel()
        viewModel.selectedID = "network"

        let inUse = Operations.NetworkDelete.Output.forbidden(
            .init(body: .json(.init(message: "network has active endpoints")))
        )
        XCTAssertFalse(viewModel.applyNetworkDeletion(inUse, id: "network"))
        XCTAssertEqual(viewModel.selectedID, "network")
        XCTAssertEqual(viewModel.lastError, "network has active endpoints")

        let generic = Operations.NetworkDelete.Output.internalServerError(
            .init(body: .json(.init(message: "network driver failed")))
        )
        XCTAssertFalse(viewModel.applyNetworkDeletion(generic, id: "network"))
        XCTAssertEqual(viewModel.selectedID, "network")
        XCTAssertEqual(viewModel.lastError, "network driver failed")

        XCTAssertTrue(viewModel.applyNetworkDeletion(.noContent, id: "network"))
        XCTAssertNil(viewModel.selectedID)
    }
}

final class ArgumentListTests: XCTestCase {
    func testParsesQuotedArgumentInput() throws {
        let cases: [(String, [String])] = [
            ("", []),
            ("one\t two\nthree", ["one", "two", "three"]),
            (#"sh -c "echo hello world""#, ["sh", "-c", "echo hello world"]),
            (#"printf '%s %s' "hello world" café"#, ["printf", "%s %s", "hello world", "café"]),
            (#"one\ two "three\"four" 'five\six'"#, ["one two", "three\"four", #"five\six"#]),
            ("\"\" ''", ["", ""]),
            (#"echo "你好 世界" 🐳"#, ["echo", "你好 世界", "🐳"]),
        ]

        for (input, expected) in cases {
            XCTAssertEqual(try ArgumentList.parse(input), expected, input)
        }
    }

    func testRejectsUnterminatedInput() {
        XCTAssertThrowsError(try ArgumentList.parse(#""unterminated"#)) {
            XCTAssertEqual($0 as? ArgumentList.ParseError, .unterminatedQuote("\""))
        }
        XCTAssertThrowsError(try ArgumentList.parse("trailing\\")) {
            XCTAssertEqual($0 as? ArgumentList.ParseError, .danglingEscape)
        }
    }
}
