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
                expected: "arcbox-helper 0.4.24"
            ).errorDescription ?? ""
        #expect(message.contains("0.4.12"))
        #expect(message.contains("0.4.24"))
        #expect(message.contains("sudo abctl _install"))
    }

    @Test func missingBinaryMessageNamesTheBinary() {
        let message = HelperInstallError.bundledBinaryMissing("arcbox-helper").errorDescription ?? ""
        #expect(message.contains("arcbox-helper"))
    }
}
