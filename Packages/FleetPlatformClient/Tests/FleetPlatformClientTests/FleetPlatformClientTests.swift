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
