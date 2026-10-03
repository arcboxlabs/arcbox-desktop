import ArcBoxClient
import XCTest

@testable import ArcBox

@MainActor
final class SandboxTemplateModelTests: XCTestCase {

    private func makeTemplate(
        name: String = "code-interpreter",
        version: String = "1.2.0"
    ) -> Arcbox_Sandbox_V1_Template {
        var template = Arcbox_Sandbox_V1_Template()
        template.name = name
        template.version = version
        template.digest = "sha256:abc"
        template.sizeBytes = 512 << 20
        return template
    }

    // MARK: - Reference

    // `reference` is what CreateSandboxRequest.template carries, so the draft
    // and published forms have to stay distinguishable: a bare name resolves to
    // the newest published version, which is a different template than the
    // draft it was cut from.

    func testPublishedReferencePinsTheVersion() {
        let template = SandboxTemplateViewModel(from: makeTemplate())
        XCTAssertEqual(template.reference, "code-interpreter:1.2.0")
        XCTAssertFalse(template.isDraft)
        XCTAssertEqual(template.displayVersion, "1.2.0")
    }

    func testDraftReferenceIsTheBareName() {
        let template = SandboxTemplateViewModel(from: makeTemplate(version: ""))
        XCTAssertEqual(template.reference, "code-interpreter")
        XCTAssertTrue(template.isDraft)
        XCTAssertEqual(template.displayVersion, "draft")
    }

    func testVersionsOfOneTemplateGetDistinctIdentities() {
        let older = SandboxTemplateViewModel(from: makeTemplate(version: "1.0.0"))
        let newer = SandboxTemplateViewModel(from: makeTemplate(version: "1.2.0"))
        XCTAssertNotEqual(older.id, newer.id)
    }

    // MARK: - Warm snapshot

    func testWarmSnapshotIsReportedOnlyWhenPresent() {
        var warm = makeTemplate()
        warm.warmSnapshotID = "snap-1"
        XCTAssertTrue(SandboxTemplateViewModel(from: warm).isWarm)
        XCTAssertFalse(SandboxTemplateViewModel(from: makeTemplate()).isWarm)
    }

    // MARK: - Defaults

    func testDefaultsAreReadFromTheTemplate() {
        var source = makeTemplate()
        source.defaults.limits.vcpus = 4
        source.defaults.limits.memoryMib = 2048
        source.defaults.cmd = ["python", "-m", "http.server"]
        source.defaults.exposedPorts = [8000]
        source.defaults.readyProbe.port = 8000

        let template = SandboxTemplateViewModel(from: source)
        XCTAssertEqual(template.defaultVcpus, 4)
        XCTAssertEqual(template.defaultMemoryMiB, 2048)
        XCTAssertEqual(template.defaultCmd, ["python", "-m", "http.server"])
        XCTAssertEqual(template.exposedPorts, [8000])
        XCTAssertTrue(template.hasReadyProbe)
    }

    // MARK: - Addressability

    // The daemon resolves a bare name to the newest published version and
    // falls back to the draft only when nothing is published, so a shadowed
    // draft must not be offered: creating from it would silently use the
    // published version instead.

    func testShadowedDraftIsNotAddressable() {
        let vm = SandboxesViewModel()
        vm.templates = [
            SandboxTemplateViewModel(from: makeTemplate(version: "1.0.0")),
            SandboxTemplateViewModel(from: makeTemplate(version: "")),
        ]
        XCTAssertEqual(vm.addressableTemplates.map(\.reference), ["code-interpreter:1.0.0"])
    }

    func testUnshadowedDraftStaysAddressable() {
        let vm = SandboxesViewModel()
        vm.templates = [
            SandboxTemplateViewModel(from: makeTemplate(version: "1.0.0")),
            SandboxTemplateViewModel(from: makeTemplate(name: "web-scraper", version: "")),
        ]
        XCTAssertEqual(
            vm.addressableTemplates.map(\.reference),
            ["code-interpreter:1.0.0", "web-scraper"]
        )
    }

    // An unset `defaults` is the common case for a promoted snapshot. Reading
    // through it must not report a ready probe the template does not have.
    func testMissingDefaultsReadAsUnset() {
        let template = SandboxTemplateViewModel(from: makeTemplate())
        XCTAssertEqual(template.defaultVcpus, 0)
        XCTAssertEqual(template.defaultMemoryMiB, 0)
        XCTAssertTrue(template.defaultCmd.isEmpty)
        XCTAssertTrue(template.exposedPorts.isEmpty)
        XCTAssertFalse(template.hasReadyProbe)
    }
}
