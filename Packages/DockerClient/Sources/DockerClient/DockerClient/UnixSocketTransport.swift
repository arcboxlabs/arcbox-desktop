import AsyncHTTPClient
import Foundation
import HTTPTypes
import NIOCore
import NIOHTTP1
import OpenAPIRuntime

/// A custom transport that routes OpenAPI requests through a Unix domain socket
/// using AsyncHTTPClient's `http+unix://` URL scheme.
struct UnixSocketTransport: ClientTransport {
    private let client: HTTPClient
    private let socketPath: String
    private let timeout: TimeAmount

    init(client: HTTPClient, socketPath: String, timeout: TimeAmount = .minutes(1)) {
        self.client = client
        self.socketPath = socketPath
        self.timeout = timeout
    }

    func send(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL,
        operationID: String
    ) async throws -> (HTTPResponse, HTTPBody?) {
        // Retry transient connection errors (socket not ready, connection reset).
        let maxRetries = 2
        var lastError: Error = URLError(.unknown)
        for attempt in 0...maxRetries {
            if attempt > 0 {
                try? await Task.sleep(for: .milliseconds(500 * attempt))
            }
            do {
                return try await sendOnce(request, body: body, baseURL: baseURL)
            } catch {
                lastError = error
                let nsError = error as NSError
                let isTransient =
                    nsError.domain == NSPOSIXErrorDomain
                    && [ECONNREFUSED, ECONNRESET, ENOTCONN, ENETDOWN].contains(Int32(nsError.code))
                guard isTransient, attempt < maxRetries else { break }
            }
        }
        throw lastError
    }

    private func sendOnce(
        _ request: HTTPRequest,
        body: HTTPBody?,
        baseURL: URL
    ) async throws -> (HTTPResponse, HTTPBody?) {
        // Build the path from baseURL + request path
        let basePath = baseURL.path  // e.g. "/v1.47"
        let requestPath = request.path ?? ""
        let fullPath = basePath + requestPath

        // Encode socket path for http+unix:// URL scheme
        let encodedSocket =
            socketPath
            .addingPercentEncoding(withAllowedCharacters: .urlHostAllowed) ?? socketPath
        let urlString = "http+unix://\(encodedSocket)\(fullPath)"

        var clientRequest = HTTPClientRequest(url: urlString)
        clientRequest.method = httpMethod(from: request.method)
        for header in request.headerFields {
            clientRequest.headers.add(name: header.name.canonicalName, value: header.value)
        }

        if let body {
            let length: HTTPClientRequest.Body.Length
            switch body.length {
            case .unknown: length = .unknown
            case .known(let count): length = .known(count)
            }
            clientRequest.body = .stream(body.map { .init(bytes: $0) }, length: length)
        }

        let httpResponse = try await client.execute(clientRequest, timeout: timeout)

        var headerFields: HTTPFields = [:]
        for header in httpResponse.headers {
            if let name = HTTPField.Name(header.name) {
                headerFields[name] = header.value
            }
        }

        let responseBody: HTTPBody?
        switch request.method {
        case .head, .connect, .trace:
            responseBody = nil
        default:
            // Eagerly collect the full body while the connection is still alive.
            // Docker often sends `connection: close` with chunked encoding,
            // which can drop the socket before a lazy consumer reads the data.
            var collected = Data()
            for try await var chunk in httpResponse.body {
                if let bytes = chunk.readBytes(length: chunk.readableBytes) {
                    collected.append(contentsOf: bytes)
                }
            }
            responseBody = HTTPBody(collected)
        }

        let response = HTTPResponse(
            status: .init(code: Int(httpResponse.status.code)),
            headerFields: headerFields
        )
        return (response, responseBody)
    }

    private func httpMethod(from method: HTTPRequest.Method) -> NIOHTTP1.HTTPMethod {
        switch method {
        case .get: return .GET
        case .put: return .PUT
        case .post: return .POST
        case .delete: return .DELETE
        case .options: return .OPTIONS
        case .head: return .HEAD
        case .patch: return .PATCH
        case .trace: return .TRACE
        default: return .RAW(value: method.rawValue)
        }
    }
}
