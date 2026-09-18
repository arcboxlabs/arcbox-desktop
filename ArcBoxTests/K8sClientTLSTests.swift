import Network
import XCTest

@testable import K8sClient

@available(macOS 15.0, *)
final class K8sClientTLSTests: XCTestCase {

    // MARK: - PEM decoding

    /// k3s ships the client certificate as a chain. Base64 pads each block on its own, so
    /// decoding the blocks as one string fails whenever the leaf's length is not a multiple
    /// of three — which, with ECDSA signatures varying in length, is most clusters.
    func testDerBlocksDecodesEachBlockOfAChainOnItsOwn() throws {
        let leaf = Data((0..<100).map { UInt8($0) })
        let authority = Data((0..<99).map { UInt8($0) })
        XCTAssertTrue(leaf.base64EncodedString().hasSuffix("="), "the leaf must need padding")

        let pem = [leaf, authority].map(Self.pemBlock).joined()

        XCTAssertEqual(try KubeConfig.derBlocks(Data(pem.utf8)), [leaf, authority])
    }

    func testDerBlocksTakesUnarmoredDataAsDER() throws {
        let der = Data([0x30, 0x82, 0x01, 0x9a, 0xff])
        XCTAssertEqual(try KubeConfig.derBlocks(der), [der])
    }

    func testDerBlocksRejectsABlockWithoutItsEndLine() {
        let pem = "-----BEGIN CERTIFICATE-----\nAAAA\n"
        XCTAssertThrowsError(try KubeConfig.derBlocks(Data(pem.utf8)))
    }

    private static func pemBlock(_ der: Data) -> String {
        let body = der.base64EncodedString(options: [.lineLength64Characters, .endLineWithLineFeed])
        return "-----BEGIN CERTIFICATE-----\n\(body)\n-----END CERTIFICATE-----\n"
    }

    // MARK: - End to end

    /// URLSession routes auth challenges differently for `data(for:)` and `bytes(for:)`, so
    /// only a real TLS socket shows whether the watch is covered by the delegate. The server
    /// chains to a private CA and demands a client certificate, as k3s does; the pod it
    /// announces exists only on the watch, never in the LIST.
    func testWatchRunsOverPinnedMutualTLS() async throws {
        let pki = try TestPKI()
        defer { pki.remove() }
        let server = try FakeAPIServer(identity: pki.serverIdentity())
        try await server.start()
        defer { server.stop() }
        let client = try K8sClient(config: KubeConfig(yaml: pki.kubeconfig(port: server.port)))

        try await withTimeout(.seconds(20)) {
            for try await pods in client.podStream()
            where pods.contains(where: { $0.metadata?.name == "watched" }) {
                return
            }
            XCTFail("The stream ended before the watch delivered its event")
        }
    }
}

// MARK: - Fixtures

private struct TimedOut: Error {}

private func withTimeout(
    _ limit: Duration,
    _ operation: @escaping @Sendable () async throws -> Void
) async throws {
    try await withThrowingTaskGroup(of: Void.self) { group in
        group.addTask(operation: operation)
        group.addTask {
            try await Task.sleep(for: limit)
            throw TimedOut()
        }
        defer { group.cancelAll() }
        try await group.next()
    }
}

/// A throwaway CA with one server and one client certificate, minted by the system
/// `openssl`. Generated per run: Apple's TLS policy rejects server certificates valid for
/// more than 825 days, so a checked-in fixture would expire under the test.
private struct TestPKI {
    struct CommandFailed: Error {
        let arguments: [String]
        let output: String
    }

    private let directory: URL

    init() throws {
        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("k8s-tls-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)

        try write(
            "ca.cnf",
            """
            [req]
            distinguished_name = dn
            x509_extensions = v3_ca
            prompt = no
            [dn]
            CN = test-ca
            [v3_ca]
            basicConstraints = critical,CA:TRUE
            keyUsage = critical,keyCertSign
            """)
        try write("server.ext", "subjectAltName=IP:127.0.0.1\nextendedKeyUsage=serverAuth\n")
        try write("client.ext", "extendedKeyUsage=clientAuth\n")

        try openssl("ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", "ca.key")
        // `-sha256` throughout: the system LibreSSL still defaults to SHA-1, which Apple's
        // trust evaluation refuses.
        try openssl(
            "req", "-x509", "-new", "-sha256", "-key", "ca.key", "-config", "ca.cnf", "-days", "30",
            "-out", "ca.crt")
        for (name, subject) in [("server", "/CN=k3s"), ("client", "/O=system:masters/CN=system:admin")] {
            try openssl("ecparam", "-name", "prime256v1", "-genkey", "-noout", "-out", "\(name).key")
            try openssl("req", "-new", "-key", "\(name).key", "-subj", subject, "-out", "\(name).csr")
            try openssl(
                "x509", "-req", "-sha256", "-in", "\(name).csr", "-CA", "ca.crt", "-CAkey", "ca.key",
                "-CAcreateserial", "-days", "30", "-extfile", "\(name).ext", "-out", "\(name).crt")
        }
    }

    func remove() {
        try? FileManager.default.removeItem(at: directory)
    }

    func serverIdentity() throws -> SecIdentity {
        try KubeTLSDelegate.createIdentity(
            certData: KubeConfig.derBlocks(read("server.crt"))[0],
            keyPEM: read("server.key"))
    }

    /// The client certificate is the leaf followed by its CA, the way k3s writes it.
    func kubeconfig(port: UInt16) throws -> String {
        let chain = try read("client.crt") + read("ca.crt")
        return """
            apiVersion: v1
            kind: Config
            current-context: default
            clusters:
            - name: default
              cluster:
                server: https://127.0.0.1:\(port)
                certificate-authority-data: \(try read("ca.crt").base64EncodedString())
            contexts:
            - name: default
              context:
                cluster: default
                user: default
            users:
            - name: default
              user:
                client-certificate-data: \(chain.base64EncodedString())
                client-key-data: \(try read("client.key").base64EncodedString())
            """
    }

    private func read(_ name: String) throws -> Data {
        try Data(contentsOf: directory.appendingPathComponent(name))
    }

    private func write(_ name: String, _ contents: String) throws {
        try Data(contents.utf8).write(to: directory.appendingPathComponent(name))
    }

    private func openssl(_ arguments: String...) throws {
        let process = Process()
        let output = Pipe()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/openssl")
        process.arguments = arguments
        process.currentDirectoryURL = directory
        process.standardOutput = output
        process.standardError = output
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            let text = String(bytes: output.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)
            throw CommandFailed(arguments: arguments, output: text ?? "")
        }
    }
}

/// Just enough of an API server for one LIST and one WATCH, behind mutual TLS.
private final class FakeAPIServer: @unchecked Sendable {
    private let listener: NWListener
    private let queue = DispatchQueue(label: "FakeAPIServer")
    /// Touched only on `queue`. Holding the connections keeps the watch open.
    private var connections: [NWConnection] = []

    var port: UInt16 { listener.port?.rawValue ?? 0 }

    init(identity: SecIdentity) throws {
        let tls = NWProtocolTLS.Options()
        let security = tls.securityProtocolOptions
        guard let localIdentity = sec_identity_create(identity) else {
            throw KubeConfigError.invalidCertificate("sec_identity_create failed")
        }
        sec_protocol_options_set_local_identity(security, localIdentity)
        sec_protocol_options_set_peer_authentication_required(security, true)
        // Any client certificate passes: that one is presented at all is what is under test.
        sec_protocol_options_set_verify_block(security, { _, _, complete in complete(true) }, queue)
        listener = try NWListener(using: NWParameters(tls: tls), on: .any)
    }

    func start() async throws {
        listener.newConnectionHandler = { [weak self] connection in self?.serve(connection) }
        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, any Error>) in
            listener.stateUpdateHandler = { [listener] state in
                switch state {
                case .ready:
                    listener.stateUpdateHandler = nil
                    continuation.resume()
                case .failed(let error):
                    listener.stateUpdateHandler = nil
                    continuation.resume(throwing: error)
                default:
                    break
                }
            }
            listener.start(queue: queue)
        }
    }

    func stop() {
        listener.cancel()
        queue.async { [self] in
            connections.forEach { $0.cancel() }
            connections.removeAll()
        }
    }

    private func serve(_ connection: NWConnection) {
        connections.append(connection)
        connection.start(queue: queue)
        receiveRequest(on: connection, buffered: Data())
    }

    private func receiveRequest(on connection: NWConnection, buffered: Data) {
        connection.receive(minimumIncompleteLength: 1, maximumLength: 8192) { [weak self] data, _, _, error in
            guard let self, error == nil, let data else { return }
            let request = buffered + data
            guard let head = String(data: request, encoding: .utf8), head.contains("\r\n\r\n") else {
                return self.receiveRequest(on: connection, buffered: request)
            }
            connection.send(content: Self.response(to: head), completion: .contentProcessed { _ in })
        }
    }

    private static func response(to requestHead: String) -> Data {
        guard requestHead.contains("watch=1") else {
            let body = #"{"kind":"PodList","apiVersion":"v1","metadata":{"resourceVersion":"10"},"items":[]}"#
            return Data(
                "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nContent-Length: \(body.utf8.count)\r\n\r\n\(body)"
                    .utf8)
        }
        let event =
            #"{"type":"ADDED","object":{"metadata":{"name":"watched","namespace":"default","uid":"u1","resourceVersion":"11"}}}"#
            + "\n"
        let chunk = "\(String(event.utf8.count, radix: 16))\r\n\(event)\r\n"
        return Data(
            "HTTP/1.1 200 OK\r\nContent-Type: application/json\r\nTransfer-Encoding: chunked\r\n\r\n\(chunk)".utf8)
    }
}
