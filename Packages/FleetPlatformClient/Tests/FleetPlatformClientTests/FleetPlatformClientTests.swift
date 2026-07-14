import ArcBoxAuth
import Foundation
import Testing

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

    @Test func issueEnrollmentTokenUsesWorkspaceHeaderAndDecodesResponse() async throws {
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

        let enrollment = try await client.issueEnrollmentToken(workspaceID: "ws_123")

        #expect(enrollment.token == "flet_secret")
    }

    @Test func mapsUnauthenticatedResponse() async {
        let http = HTTPStub { request in
            (Data(), try response(for: request, statusCode: 401))
        }
        let client = makeClient(http: http)

        await #expect(throws: FleetPlatformError.unauthenticated) {
            try await client.listWorkspaces()
        }
    }

    @Test func preservesAIP193ErrorMessage() async {
        let json = """
            {"error":[{"code":429,"status":"RESOURCE_EXHAUSTED",\
            "message":"Fleet enrollment token limit reached"}]}
            """
        let http = HTTPStub { request in
            (Data(json.utf8), try response(for: request, statusCode: 429))
        }
        let client = makeClient(http: http)

        await #expect(
            throws: FleetPlatformError.api(
                statusCode: 429,
                status: "RESOURCE_EXHAUSTED",
                message: "Fleet enrollment token limit reached"
            )
        ) {
            try await client.listWorkspaces()
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

    @Test func propagatesCancellation() async {
        let http = HTTPStub { _ in throw CancellationError() }
        let client = makeClient(http: http)

        await #expect(throws: CancellationError.self) {
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

    private func makeClient(http: any HTTPDataLoading) -> FleetPlatformClient {
        FleetPlatformClient(
            configuration: configuration,
            accessTokenProvider: StubTokenProvider(),
            http: http
        )
    }
}

private struct StubTokenProvider: AccessTokenProviding {
    func accessToken() async throws -> String {
        "oidc-token"
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
