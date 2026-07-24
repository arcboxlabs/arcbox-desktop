// System modules precede local packages per the repository import-order guideline.
// swift-format-ignore: OrderedImports
import Foundation
import Testing
import ArcBoxAuth

@testable import FleetPlatformClient

struct FleetPlatformClientTests {
    private let configuration = FleetPlatformConfiguration(
        baseURL: URL(string: "https://api.example.com/root")!
    )

    @Test func listWorkspacesBuildsAuthenticatedRequestAndDecodesResponse() async throws {
        let json = """
            [{
              "id":"ws_123",
              "name":"ArcBox Labs",
              "plan":"free",
              "created_at":"2026-07-14T12:34:56.123456Z",
              "updated_at":"2026-07-14T13:34:56Z"
            }]
            """
        let http = HTTPStub { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.absoluteString == "https://api.example.com/root/v1/workspaces")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer oidc-token")
            #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
            return (Data(json.utf8), try response(for: request))
        }
        let client = makeClient(http: http)

        let workspaces = try await client.listWorkspaces()

        #expect(workspaces.count == 1)
        #expect(workspaces.first?.id == "ws_123")
        #expect(workspaces.first?.name == "ArcBox Labs")
        #expect(workspaces.first?.plan == "free")
    }

    @Test func createEnrollmentTokenUsesWorkspaceHeaderAndDecodesResponse() async throws {
        let json = #"{"token":"flet_secret","expires_at":"2026-07-14T14:34:56.123Z"}"#
        let http = HTTPStub { request in
            #expect(request.httpMethod == "POST")
            #expect(
                request.url?.absoluteString
                    == "https://api.example.com/root/v1/fleet/enrollment-token"
            )
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer oidc-token")
            #expect(request.value(forHTTPHeaderField: "X-Workspace-Id") == "ws_123")
            #expect(request.httpBody == nil)
            return (Data(json.utf8), try response(for: request))
        }
        let client = makeClient(http: http)

        let enrollment = try await client.createEnrollmentToken(workspaceID: "ws_123")

        #expect(enrollment.token == "flet_secret")
    }

    @Test func listMachinesUsesWorkspaceHeaderAndDecodesResponse() async throws {
        let json = """
            [{
              "id":"fltm_123",
              "name":"Shuo's Mac",
              "status":"online",
              "arch":"arm64",
              "cpu":12,
              "mem_mib":24576,
              "host_info":{"hostname":"studio"},
              "tags":["desktop"],
              "created_at":"2026-07-24T08:00:00Z",
              "enrolled_at":"2026-07-24T08:01:00Z",
              "last_seen":"2026-07-24T08:02:00.123Z",
              "agent_version":"0.5.1",
              "pools":[{"os":"darwin","arch":"arm64","backed_by":"vm"}],
              "telemetry":{
                "load_avg_1m":1.25,
                "cpu_count":12,
                "mem_total_mib":24576,
                "mem_available_mib":16384
              }
            }]
            """
        let http = HTTPStub { request in
            #expect(request.httpMethod == "GET")
            #expect(request.url?.absoluteString == "https://api.example.com/root/v1/fleet/machines")
            #expect(request.value(forHTTPHeaderField: "X-Workspace-Id") == "ws_123")
            return (Data(json.utf8), try response(for: request))
        }
        let client = makeClient(http: http)

        let machines = try await client.listMachines(workspaceID: "ws_123")

        let machine = try #require(machines.first)
        #expect(machine.id == "fltm_123")
        #expect(machine.status == .online)
        #expect(machine.agentVersion == "0.5.1")
        #expect(machine.pools == [.init(os: .darwin, arch: .arm64, backedBy: .vm)])
        #expect(machine.telemetry?.memAvailableMib == 16384)
    }

    @Test func getMachineUsesOpaquePrefixedID() async throws {
        let json = """
            {
              "id":"fltm_abc",
              "name":"This Mac",
              "status":"enrolled",
              "arch":"arm64",
              "cpu":8,
              "mem_mib":16384,
              "host_info":{},
              "tags":[],
              "created_at":"2026-07-24T08:00:00Z",
              "pools":[]
            }
            """
        let http = HTTPStub { request in
            #expect(
                request.url?.absoluteString
                    == "https://api.example.com/root/v1/fleet/machines/fltm_abc"
            )
            #expect(request.value(forHTTPHeaderField: "X-Workspace-Id") == "ws_123")
            return (Data(json.utf8), try response(for: request))
        }
        let client = makeClient(http: http)

        let machine = try await client.getMachine(id: "fltm_abc", workspaceID: "ws_123")

        #expect(machine.id == "fltm_abc")
    }

    @Test func listJobsBuildsFiltersAndDecodesCursorPage() async throws {
        let json = """
            {
              "jobs":[{
                "id":"5ce49702-bb18-4a15-9ee5-91a62619799a",
                "repo":"arcboxlabs/arcbox",
                "status":"running",
                "os":"linux",
                "arch":"amd64",
                "gh_run_id":123,
                "gh_job_id":456,
                "labels":["self-hosted","linux"],
                "machine_id":"fltm_abc",
                "jit_runner_name":"arcbox-123",
                "created_at":"2026-07-24T08:00:00Z",
                "started_at":"2026-07-24T08:00:05Z"
              }],
              "next_cursor":"next-page"
            }
            """
        let http = HTTPStub { request in
            #expect(request.httpMethod == "GET")
            let url = try #require(request.url)
            let components = try #require(
                URLComponents(url: url, resolvingAgainstBaseURL: false)
            )
            #expect(components.path == "/root/v1/fleet/jobs")
            #expect(
                components.queryItems
                    == [
                        URLQueryItem(name: "machine_id", value: "fltm_abc"),
                        URLQueryItem(name: "status", value: "running"),
                        URLQueryItem(name: "cursor", value: "older"),
                        URLQueryItem(name: "limit", value: "25"),
                    ]
            )
            #expect(request.value(forHTTPHeaderField: "X-Workspace-Id") == "ws_123")
            return (Data(json.utf8), try response(for: request))
        }
        let client = makeClient(http: http)

        let page = try await client.listJobs(
            workspaceID: "ws_123",
            machineID: "fltm_abc",
            status: .running,
            cursor: "older",
            limit: 25
        )

        let job = try #require(page.jobs.first)
        #expect(job.machineID == "fltm_abc")
        #expect(job.githubRunID == 123)
        #expect(job.githubJobID == 456)
        #expect(job.status == .running)
        #expect(job.os == .linux)
        #expect(job.arch == .amd64)
        #expect(page.nextCursor == "next-page")
    }

    @Test func getJobBuildsWorkspaceScopedRequest() async throws {
        let json = """
            {
              "id":"5ce49702-bb18-4a15-9ee5-91a62619799a",
              "repo":"arcboxlabs/arcbox",
              "status":"completed",
              "os":"darwin",
              "arch":"arm64",
              "gh_run_id":123,
              "gh_job_id":456,
              "labels":[],
              "created_at":"2026-07-24T08:00:00Z",
              "finished_at":"2026-07-24T08:01:00Z"
            }
            """
        let http = HTTPStub { request in
            #expect(
                request.url?.absoluteString
                    == "https://api.example.com/root/v1/fleet/jobs/"
                    + "5ce49702-bb18-4a15-9ee5-91a62619799a"
            )
            #expect(request.value(forHTTPHeaderField: "X-Workspace-Id") == "ws_123")
            return (Data(json.utf8), try response(for: request))
        }
        let client = makeClient(http: http)

        let job = try await client.getJob(
            id: "5ce49702-bb18-4a15-9ee5-91a62619799a",
            workspaceID: "ws_123"
        )

        #expect(job.status == .completed)
        #expect(job.finishedAt != nil)
    }

    @Test func requestsAValidAccessTokenEveryTime() async throws {
        let tokenProvider = CountingTokenProvider()
        let http = HTTPStub { request in
            (Data("[]".utf8), try response(for: request))
        }
        let client = makeClient(accessTokenProvider: tokenProvider, http: http)

        _ = try await client.listWorkspaces()
        _ = try await client.listWorkspaces()

        #expect(await tokenProvider.callCount == 2)
    }

    @Test func mapsKnownHTTPStatusResponses() async {
        let cases: [(Int, FleetPlatformError)] = [
            (401, .authenticationRequired),
            (403, .forbidden),
            (404, .notFound),
            (409, .conflict),
            (429, .rateLimited),
            (503, .serverError(statusCode: 503)),
        ]

        for (statusCode, expectedError) in cases {
            let http = HTTPStub { request in
                (Data(), try response(for: request, statusCode: statusCode))
            }
            let client = makeClient(http: http)

            await #expect(throws: expectedError) {
                try await client.listWorkspaces()
            }
        }
    }

    @Test func serverMessageCannotExposeEnrollmentToken() async {
        let secret = "flet_super_secret"
        let json = """
            {"error":[{"code":422,"status":"INVALID_ARGUMENT",\
            "message":"Rejected token: \(secret)"}]}
            """
        let http = HTTPStub { request in
            (Data(json.utf8), try response(for: request, statusCode: 422))
        }
        let client = makeClient(http: http)

        do {
            _ = try await client.listWorkspaces()
            Issue.record("Expected the request to fail")
        } catch {
            #expect(error as? FleetPlatformError == .api(statusCode: 422))
            #expect(!error.localizedDescription.contains(secret))
            #expect(!String(describing: error).contains(secret))
        }
    }

    @Test func rejectsMalformedSuccessPayload() async {
        let http = HTTPStub { request in
            (Data("not json".utf8), try response(for: request))
        }
        let client = makeClient(http: http)

        await #expect(throws: FleetPlatformError.malformedResponse) {
            try await client.listWorkspaces()
        }
    }

    @Test func rejectsSuccessPayloadMissingRequiredFields() async {
        let http = HTTPStub { request in
            (Data(#"{"token":"flet_secret"}"#.utf8), try response(for: request))
        }
        let client = makeClient(http: http)

        await #expect(throws: FleetPlatformError.malformedResponse) {
            try await client.createEnrollmentToken(workspaceID: "ws_123")
        }
    }

    @Test func propagatesCancellation() async {
        let http = HTTPStub { _ in throw CancellationError() }
        let client = makeClient(http: http)

        await #expect(throws: CancellationError.self) {
            try await client.listWorkspaces()
        }
    }

    @Test func mapsURLSessionTransportFailureWithoutRequestDetails() async {
        let http = HTTPStub { _ in throw URLError(.cannotConnectToHost) }
        let client = makeClient(http: http)

        await #expect(
            throws: FleetPlatformError.transport(code: .cannotConnectToHost)
        ) {
            try await client.listWorkspaces()
        }
    }

    @Test func rejectsNonHTTPResponse() async {
        let http = HTTPStub { request in
            let url = try #require(request.url)
            return (
                Data("[]".utf8),
                URLResponse(
                    url: url,
                    mimeType: "application/json",
                    expectedContentLength: 2,
                    textEncodingName: nil
                )
            )
        }
        let client = makeClient(http: http)

        await #expect(throws: FleetPlatformError.invalidResponse) {
            try await client.listWorkspaces()
        }
    }

    @Test func rejectsInvalidConfiguredBaseURL() {
        #expect(FleetPlatformConfiguration.resolve(baseURL: "not-a-url") == nil)
        #expect(FleetPlatformConfiguration.resolve(baseURL: "$(FLEET_PLATFORM_BASE_URL)") == nil)
        #expect(
            FleetPlatformConfiguration.resolve(baseURL: "http://localhost:2801")?.baseURL
                == URL(string: "http://localhost:2801")
        )
    }

    private func makeClient(
        accessTokenProvider: any AccessTokenProviding = StubTokenProvider(),
        http: any HTTPDataLoading
    ) -> FleetPlatformClient {
        FleetPlatformClient(
            configuration: configuration,
            accessTokenProvider: accessTokenProvider,
            http: http
        )
    }
}

private struct StubTokenProvider: AccessTokenProviding {
    func accessToken() async throws -> String {
        "oidc-token"
    }
}

private actor CountingTokenProvider: AccessTokenProviding {
    private(set) var callCount = 0

    func accessToken() async throws -> String {
        callCount += 1
        return "oidc-token"
    }
}

private actor HTTPStub: HTTPDataLoading {
    private let handler: @Sendable (URLRequest) async throws -> (Data, URLResponse)

    init(handler: @escaping @Sendable (URLRequest) async throws -> (Data, URLResponse)) {
        self.handler = handler
    }

    func data(for request: URLRequest) async throws -> (Data, URLResponse) {
        try await handler(request)
    }
}

private func response(for request: URLRequest, statusCode: Int = 200) throws -> HTTPURLResponse {
    let url = try #require(request.url)
    return try #require(
        HTTPURLResponse(
            url: url,
            statusCode: statusCode,
            httpVersion: "HTTP/2",
            headerFields: ["Content-Type": "application/json"]
        )
    )
}
