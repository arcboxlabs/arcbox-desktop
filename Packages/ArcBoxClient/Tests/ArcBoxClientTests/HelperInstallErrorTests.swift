import Testing

@testable import ArcBoxClient

struct HelperInstallErrorTests {
    @Test func userCanceledMessageMentionsRetryAndDocker() {
        let message = HelperInstallError.userCanceled.errorDescription ?? ""
        #expect(message.contains("Retry"))
        #expect(message.contains("/usr/local/bin/docker"))
    }

    @Test func versionMismatchMessageIncludesBothVersions() {
        let message =
            HelperInstallError.versionMismatch(
                installed: "arcbox-helper 0.4.12",
                expected: "arcbox-helper 1.0.0"
            ).errorDescription ?? ""
        #expect(message.contains("0.4.12"))
        #expect(message.contains("1.0.0"))
        #expect(message.contains("sudo abctl _install"))
    }

    @Test func missingBinaryMessageNamesTheBinary() {
        let message = HelperInstallError.bundledBinaryMissing("arcbox-helper").errorDescription ?? ""
        #expect(message.contains("arcbox-helper"))
    }
}

struct HelperVersionTests {
    @Test func parsesIndependentHelperVersion() {
        let v = HelperVersion.parse("arcbox-helper 1.0.0")
        #expect(v?.major == 1)
        #expect(v?.minor == 0)
        #expect(v?.patch == 0)
    }

    @Test func parsesLegacyWorkspaceTiedVersion() {
        let v = HelperVersion.parse("arcbox-helper 0.4.12")
        #expect(v?.major == 0)
        #expect(v?.minor == 4)
        #expect(v?.patch == 12)
    }

    @Test func rejectsGarbageAndNil() {
        #expect(HelperVersion.parse(nil) == nil)
        #expect(HelperVersion.parse("") == nil)
        #expect(HelperVersion.parse("not-a-helper") == nil)
    }

    @Test func reinstallOnlyWhenStrictlyOlder() {
        let v100: HelperVersion.Triple = (1, 0, 0)
        let v012: HelperVersion.Triple = (0, 4, 12)
        let v101: HelperVersion.Triple = (1, 0, 1)

        #expect(HelperVersion.needsReinstall(installed: nil, bundled: v100))
        #expect(HelperVersion.needsReinstall(installed: v012, bundled: v100))
        #expect(!HelperVersion.needsReinstall(installed: v100, bundled: v100))
        #expect(!HelperVersion.needsReinstall(installed: v101, bundled: v100))
        #expect(HelperVersion.needsReinstall(installed: v100, bundled: nil))
    }
}
