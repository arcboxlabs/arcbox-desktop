import Foundation
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

    @Test func rejectsMalformedSemverComponents() {
        #expect(HelperVersion.parse("arcbox-helper 1.garbage.9") == nil)
        #expect(HelperVersion.parse("arcbox-helper 1.2.garbage") == nil)
        #expect(HelperVersion.parse("arcbox-helper 1.2") == nil)
        #expect(HelperVersion.parse("arcbox-helper 1.2.3.4") == nil)
    }

    @Test func reinstallOnlyWhenStrictlyOlder() {
        let v100 = HelperVersion(major: 1, minor: 0, patch: 0)
        let v012 = HelperVersion(major: 0, minor: 4, patch: 12)
        let v101 = HelperVersion(major: 1, minor: 0, patch: 1)
        let v200 = HelperVersion(major: 2, minor: 0, patch: 0)

        #expect(HelperVersion.needsReinstall(installed: nil, bundled: v100))
        #expect(HelperVersion.needsReinstall(installed: v012, bundled: v100))
        #expect(!HelperVersion.needsReinstall(installed: v100, bundled: v100))
        #expect(!HelperVersion.needsReinstall(installed: v101, bundled: v100))
        #expect(HelperVersion.needsReinstall(installed: v100, bundled: nil))
        // Major mismatch either way is a wire break — always reinstall.
        #expect(HelperVersion.needsReinstall(installed: v200, bundled: v100))
        #expect(HelperVersion.needsReinstall(installed: v100, bundled: v200))
    }
}

struct AppleScriptStringLiteralTests {
    @Test func untrustedPathCharactersRoundTripAsData() throws {
        let value = "ArcBox\" & (do shell script \"printf injected\") & \\.app\nnext\rline\ttab"
        let source = "return \(appleScriptStringLiteral(value))"
        var error: NSDictionary?

        let script = try #require(NSAppleScript(source: source))
        let result = script.executeAndReturnError(&error)

        #expect(error == nil)
        #expect(result.stringValue == value)
    }
}
