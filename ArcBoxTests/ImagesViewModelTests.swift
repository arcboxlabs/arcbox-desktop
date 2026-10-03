import DockerClient
import XCTest

@testable import ArcBox

@MainActor
final class ImagesViewModelTests: XCTestCase {

    private var vm: ImagesViewModel!

    override func setUp() {
        super.setUp()
        vm = ImagesViewModel()
    }

    // MARK: - Initial State

    func testInitialState() {
        XCTAssertTrue(vm.images.isEmpty)
        XCTAssertNil(vm.selectedID)
        XCTAssertEqual(vm.loadState, .waiting)
        XCTAssertNil(vm.refreshError)
        XCTAssertNil(vm.lastError)
    }

    // MARK: - Selection

    func testSelectImage() {
        vm.selectImage("img-1")
        XCTAssertEqual(vm.selectedID, "img-1")
    }

    func testSelectImageOverwritesPrevious() {
        vm.selectImage("first")
        vm.selectImage("second")
        XCTAssertEqual(vm.selectedID, "second")
    }

    func testSelectedImageNilWhenNoMatch() {
        vm.selectImage("nonexistent")
        XCTAssertNil(vm.selectedImage)
    }

    func testSelectedImageReturnsMatch() {
        let img = makeImage(id: "img-1", repository: "nginx", tag: "latest")
        vm.images = [img]
        vm.selectImage("img-1")
        XCTAssertEqual(vm.selectedImage?.id, "img-1")
    }

    // MARK: - Total Size

    func testTotalSizeEmpty() {
        XCTAssertEqual(vm.totalSize, "0.0 MB total")
    }

    func testTotalSizeMB() {
        vm.images = [
            makeImage(id: "1", repository: "a", tag: "1", sizeBytes: 50_000_000),
            makeImage(id: "2", repository: "b", tag: "1", sizeBytes: 150_000_000),
        ]
        XCTAssertEqual(vm.totalSize, "200.0 MB total")
    }

    func testTotalSizeGB() {
        vm.images = [
            makeImage(id: "1", repository: "a", tag: "1", sizeBytes: 2_500_000_000)
        ]
        XCTAssertEqual(vm.totalSize, "2.50 GB total")
    }

    // MARK: - Sorted Images

    func testSortedImagesEmpty() {
        XCTAssertTrue(vm.sortedImages.isEmpty)
    }

    func testSortedImagesByNameAscending() {
        vm.images = [
            makeImage(id: "2", repository: "redis", tag: "7"),
            makeImage(id: "1", repository: "nginx", tag: "latest"),
        ]
        vm.sortBy = .name
        vm.sortAscending = true
        XCTAssertEqual(vm.sortedImages.map(\.repository), ["nginx", "redis"])
    }

    func testSortedImagesByNameDescending() {
        vm.images = [
            makeImage(id: "1", repository: "nginx", tag: "latest"),
            makeImage(id: "2", repository: "redis", tag: "7"),
        ]
        vm.sortBy = .name
        vm.sortAscending = false
        XCTAssertEqual(vm.sortedImages.map(\.repository), ["redis", "nginx"])
    }

    func testDescendingSortUsesIDToBreakEqualValues() {
        vm.sortAscending = false

        for ids in [["a", "b"], ["b", "a"]] {
            vm.images = ids.map {
                makeImage(id: $0, repository: "same", tag: "latest")
            }
            XCTAssertEqual(vm.sortedImages.map(\.id), ["b", "a"])
        }

        for ids in [["A", "a"], ["a", "A"]] {
            vm.images = ids.map {
                makeImage(id: $0, repository: "same", tag: "latest")
            }
            XCTAssertEqual(vm.sortedImages.map(\.id), ["a", "A"])
        }
    }

    func testSortedImagesBySize() {
        vm.images = [
            makeImage(id: "1", repository: "big", tag: "1", sizeBytes: 500_000_000),
            makeImage(id: "2", repository: "small", tag: "1", sizeBytes: 10_000_000),
        ]
        vm.sortBy = .size
        vm.sortAscending = true
        XCTAssertEqual(vm.sortedImages.map(\.repository), ["small", "big"])
    }

    func testMissingZeroPartialAndValidMetadataDoesNotRenderPlaceholders() {
        let unknown = makeImage(
            id: "unknown",
            repository: "unknown",
            tag: "latest",
            createdAt: nil,
            os: "",
            architecture: ""
        )
        XCTAssertEqual(unknown.createdAgo, "Unknown")
        XCTAssertNil(unknown.platformDisplay)
        XCTAssertEqual(
            makeImage(
                id: "zero",
                repository: "zero",
                tag: "latest",
                createdAt: Date(timeIntervalSince1970: 0)
            ).createdAgo,
            "Unknown"
        )

        XCTAssertEqual(
            makeImage(
                id: "os",
                repository: "os",
                tag: "latest",
                os: "linux",
                architecture: ""
            ).platformDisplay,
            "linux"
        )
        XCTAssertEqual(
            makeImage(
                id: "architecture",
                repository: "architecture",
                tag: "latest",
                os: "",
                architecture: "arm64"
            ).platformDisplay,
            "arm64"
        )
        XCTAssertEqual(
            makeImage(
                id: "valid",
                repository: "valid",
                tag: "latest",
                os: "linux",
                architecture: "arm64"
            ).platformDisplay,
            "linux/arm64"
        )
    }

    func testImageMetadataInspectionKeepsSuccessfulResultsWhenOneInspectFails() async throws {
        struct InspectFailure: Error {}

        let metadata = try await ImagesViewModel.inspectImageMetadata(
            imageIDs: ["missing", "present"]
        ) { id in
            if id == "missing" { throw InspectFailure() }
            return ImageInspectSnapshot(labels: [:], os: "linux", architecture: "arm64")
        }

        XCTAssertNil(metadata["missing"])
        XCTAssertEqual(metadata["present"]?.os, "linux")
        XCTAssertEqual(metadata["present"]?.architecture, "arm64")
    }

    func testImageMetadataInspectionPropagatesCancellation() async {
        do {
            _ = try await ImagesViewModel.inspectImageMetadata(imageIDs: ["image"]) { _ in
                throw CancellationError()
            }
            XCTFail("Expected cancellation")
        } catch is CancellationError {
        } catch {
            XCTFail("Expected CancellationError, got \(error)")
        }
    }

    // MARK: - Search Filtering

    func testSearchFiltersByRepository() {
        vm.images = [
            makeImage(id: "1", repository: "nginx", tag: "latest"),
            makeImage(id: "2", repository: "redis", tag: "7"),
        ]
        vm.searchText = "nginx"
        XCTAssertEqual(vm.sortedImages.count, 1)
        XCTAssertEqual(vm.sortedImages.first?.repository, "nginx")
    }

    func testSearchFiltersByTag() {
        vm.images = [
            makeImage(id: "1", repository: "nginx", tag: "alpine"),
            makeImage(id: "2", repository: "nginx", tag: "bullseye"),
        ]
        vm.searchText = "alpine"
        XCTAssertEqual(vm.sortedImages.count, 1)
        XCTAssertEqual(vm.sortedImages.first?.tag, "alpine")
    }

    func testSearchIsCaseInsensitive() {
        vm.images = [
            makeImage(id: "1", repository: "Nginx", tag: "latest")
        ]
        vm.searchText = "nginx"
        XCTAssertEqual(vm.sortedImages.count, 1)
    }

    // MARK: - Helpers

    private func makeImage(
        id: String,
        repository: String,
        tag: String,
        sizeBytes: UInt64 = 0,
        createdAt: Date? = Date(),
        os: String = "linux",
        architecture: String = "arm64"
    ) -> ImageViewModel {
        ImageViewModel(
            id: id,
            dockerId: "sha256:\(id)",
            repository: repository,
            tag: tag,
            sizeBytes: sizeBytes,
            createdAt: createdAt,
            inUse: false,
            os: os,
            architecture: architecture
        )
    }
}
