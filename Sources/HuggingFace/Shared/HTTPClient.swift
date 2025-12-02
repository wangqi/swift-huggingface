import Foundation
import EventSource

#if canImport(FoundationNetworking)
    import FoundationNetworking
#endif

/// HTTP methods supported by the client.
enum HTTPMethod: String, Hashable, Sendable {
    case get = "GET"
    case post = "POST"
    case put = "PUT"
    case delete = "DELETE"
    case patch = "PATCH"
    case head = "HEAD"
}

/// Base HTTP client with common functionality for all Hugging Face API clients.
final class HTTPClient: @unchecked Sendable {
    /// The host URL for requests.
    let host: URL

    /// The value for the `User-Agent` header sent in requests, if any.
    let userAgent: String?

    /// The token provider for authentication.
    let tokenProvider: TokenProvider

    /// The underlying URL session.
    let session: URLSession

    // wangqi 2025-12-02: Add middleware support for debugging
    /// The middlewares for intercepting HTTP requests and responses.
    let middlewares: [HuggingFaceMiddleware]

    /// A shared JSON decoder with consistent configuration.
    private let jsonDecoder: JSONDecoder = {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601WithFractionalSeconds
        return decoder
    }()

    /// Creates a new HTTP client.
    /// - Parameters:
    ///   - host: The host URL for requests.
    ///   - userAgent: The value for the `User-Agent` header sent in requests.
    ///   - tokenProvider: The token provider for authentication.
    ///   - session: The underlying URL session.
    ///   - middlewares: The middlewares for intercepting HTTP requests and responses.
    // wangqi 2025-12-02: Updated initializer with middlewares parameter
    init(
        host: URL,
        userAgent: String? = nil,
        tokenProvider: TokenProvider = .environment,
        session: URLSession = URLSession(configuration: .default),
        middlewares: [HuggingFaceMiddleware] = []
    ) {
        var host = host
        if !host.path.hasSuffix("/") {
            host = host.appendingPathComponent("")
        }

        self.host = host
        self.userAgent = userAgent
        self.tokenProvider = tokenProvider
        self.session = session
        self.middlewares = middlewares
    }

    private struct ClientErrorResponse: Decodable {
        let error: String
    }

    // MARK: - Request Methods

    func fetch<T: Decodable>(
        _ method: HTTPMethod,
        _ path: String,
        params: [String: Value]? = nil,
        headers: [String: String]? = nil
    ) async throws -> T {
        var request = try createRequest(method, path, params: params, headers: headers)

        // wangqi 2025-12-02: Apply request middlewares
        for middleware in middlewares {
            request = middleware.intercept(request: request)
        }

        do {
            let (data, response) = try await session.data(for: request)
            let httpResponse = try validateResponse(response, data: data)

            // wangqi 2025-12-02: Apply response middlewares
            var interceptedData = data
            for middleware in middlewares {
                let result = middleware.intercept(response: httpResponse, request: request, data: interceptedData)
                interceptedData = result.data ?? interceptedData
            }

            if T.self == Bool.self {
                // If T is Bool, we return true for successful response
                return true as! T
            } else if interceptedData.isEmpty {
                throw HTTPClientError.responseError(response: httpResponse, detail: "Empty response body")
            } else {
                do {
                    return try jsonDecoder.decode(T.self, from: interceptedData)
                } catch {
                    throw HTTPClientError.decodingError(
                        response: httpResponse,
                        detail: "Error decoding response: \(error.localizedDescription)"
                    )
                }
            }
        } catch {
            // wangqi 2025-12-02: Apply error middlewares
            for middleware in middlewares {
                middleware.interceptError(response: nil, request: request, data: nil, error: error)
            }
            throw error
        }
    }

    func fetchPaginated<T: Decodable>(
        _ method: HTTPMethod,
        _ path: String,
        params: [String: Value]? = nil,
        headers: [String: String]? = nil
    ) async throws -> PaginatedResponse<T> {
        var request = try createRequest(method, path, params: params, headers: headers)

        // wangqi 2025-12-02: Apply request middlewares
        for middleware in middlewares {
            request = middleware.intercept(request: request)
        }

        do {
            let (data, response) = try await session.data(for: request)
            let httpResponse = try validateResponse(response, data: data)

            // wangqi 2025-12-02: Apply response middlewares
            var interceptedData = data
            for middleware in middlewares {
                let result = middleware.intercept(response: httpResponse, request: request, data: interceptedData)
                interceptedData = result.data ?? interceptedData
            }

            do {
                let items = try jsonDecoder.decode([T].self, from: interceptedData)
                let nextURL = httpResponse.nextPageURL()
                return PaginatedResponse(items: items, nextURL: nextURL)
            } catch {
                throw HTTPClientError.decodingError(
                    response: httpResponse,
                    detail: "Error decoding response: \(error.localizedDescription)"
                )
            }
        } catch {
            // wangqi 2025-12-02: Apply error middlewares
            for middleware in middlewares {
                middleware.interceptError(response: nil, request: request, data: nil, error: error)
            }
            throw error
        }
    }

    func fetchStream<T: Decodable & Sendable>(
        _ method: HTTPMethod,
        _ path: String,
        params: [String: Value]? = nil,
        headers: [String: String]? = nil
    ) -> AsyncThrowingStream<T, Swift.Error> {
        // wangqi 2025-12-02: Capture middlewares for use in async context
        let capturedMiddlewares = self.middlewares

        return AsyncThrowingStream { @Sendable continuation in
            let task = Task {
                do {
                    var request = try createRequest(method, path, params: params, headers: headers)

                    // wangqi 2025-12-02: Apply request middlewares
                    for middleware in capturedMiddlewares {
                        request = middleware.intercept(request: request)
                    }

                    let (bytes, response) = try await session.bytes(for: request)
                    let httpResponse = try validateResponse(response)

                    guard (200 ..< 300).contains(httpResponse.statusCode) else {
                        var errorData = Data()
                        for try await byte in bytes {
                            errorData.append(byte)
                        }
                        // wangqi 2025-12-02: Apply error middlewares for non-2xx responses
                        for middleware in capturedMiddlewares {
                            middleware.interceptError(response: httpResponse, request: request, data: errorData, error: nil)
                        }
                        // validateResponse will throw the appropriate error
                        _ = try validateResponse(response, data: errorData)
                        return  // This line will never be reached, but satisfies the compiler
                    }

                    for try await event in bytes.events {
                        // wangqi 2025-12-02: Apply streaming line middlewares
                        var eventData = event.data
                        for middleware in capturedMiddlewares {
                            eventData = middleware.interceptStreamingLine(request: request, eventData)
                        }

                        // Check for [DONE] signal
                        if eventData.trimmingCharacters(in: .whitespacesAndNewlines) == "[DONE]" {
                            continuation.finish()
                            return
                        }

                        guard let jsonData = eventData.data(using: .utf8) else {
                            continue
                        }

                        do {
                            let decoded = try jsonDecoder.decode(T.self, from: jsonData)
                            continuation.yield(decoded)
                        } catch {
                            // Log decoding errors but don't fail the stream
                            // This allows the stream to continue even if individual chunks fail
                            print("Warning: Failed to decode streaming response chunk: \(error)")
                        }
                    }

                    continuation.finish()
                } catch {
                    // wangqi 2025-12-02: Apply error middlewares
                    for middleware in capturedMiddlewares {
                        middleware.interceptError(response: nil, request: nil, data: nil, error: error)
                    }
                    continuation.finish(throwing: error)
                }
            }

            continuation.onTermination = { _ in
                task.cancel()
            }
        }
    }

    func fetchData(
        _ method: HTTPMethod,
        _ path: String,
        params: [String: Value]? = nil,
        headers: [String: String]? = nil
    ) async throws -> Data {
        var request = try createRequest(method, path, params: params, headers: headers)

        // wangqi 2025-12-02: Apply request middlewares
        for middleware in middlewares {
            request = middleware.intercept(request: request)
        }

        do {
            let (data, response) = try await session.data(for: request)
            let httpResponse = try validateResponse(response, data: data)

            // wangqi 2025-12-02: Apply response middlewares
            var interceptedData = data
            for middleware in middlewares {
                let result = middleware.intercept(response: httpResponse, request: request, data: interceptedData)
                interceptedData = result.data ?? interceptedData
            }

            return interceptedData
        } catch {
            // wangqi 2025-12-02: Apply error middlewares
            for middleware in middlewares {
                middleware.interceptError(response: nil, request: request, data: nil, error: error)
            }
            throw error
        }
    }

    func createRequest(
        _ method: HTTPMethod,
        _ path: String,
        params: [String: Value]? = nil,
        headers: [String: String]? = nil
    ) throws -> URLRequest {
        var urlComponents = URLComponents(url: host, resolvingAgainstBaseURL: true)
        urlComponents?.path = path

        var httpBody: Data? = nil
        switch method {
        case .get, .head:
            if let params {
                var queryItems: [URLQueryItem] = []
                for (key, value) in params {
                    queryItems.append(URLQueryItem(name: key, value: value.description))
                }
                urlComponents?.queryItems = queryItems
            }
        case .post, .put, .delete, .patch:
            if let params {
                let encoder = JSONEncoder()
                // Special-case: allow sending a top-level JSON value (e.g., array)
                // by passing a single empty-string key.
                // This is used for endpoints that require an array body instead of an object.
                if params.count == 1, let sole = params.first, sole.key == "" {
                    httpBody = try encoder.encode(sole.value)
                } else {
                    httpBody = try encoder.encode(params)
                }
            }
        }

        guard let url = urlComponents?.url else {
            throw HTTPClientError.requestError(
                #"Unable to construct URL with host "\#(host)" and path "\#(path)""#
            )
        }
        var request: URLRequest = URLRequest(url: url)
        request.httpMethod = method.rawValue

        request.addValue("application/json", forHTTPHeaderField: "Accept")
        if let userAgent {
            request.addValue(userAgent, forHTTPHeaderField: "User-Agent")
        }

        // Get authentication token from provider
        if let token = try tokenProvider.getToken() {
            request.addValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }

        if let httpBody {
            request.httpBody = httpBody
            request.addValue("application/json", forHTTPHeaderField: "Content-Type")
        }

        // Add custom headers
        if let headers {
            for (key, value) in headers {
                request.addValue(value, forHTTPHeaderField: key)
            }
        }

        return request
    }

    func validateResponse(_ response: URLResponse, data: Data? = nil) throws -> HTTPURLResponse {
        guard let httpResponse = response as? HTTPURLResponse else {
            throw HTTPClientError.unexpectedError("Invalid response from server: \(response)")
        }

        // If we have data and it's an error status, parse and throw the error
        if let data = data, !(200 ..< 300).contains(httpResponse.statusCode) {
            if let errorDetail = try? jsonDecoder.decode(ClientErrorResponse.self, from: data) {
                throw HTTPClientError.responseError(response: httpResponse, detail: errorDetail.error)
            }

            if let string = String(data: data, encoding: .utf8) {
                throw HTTPClientError.responseError(response: httpResponse, detail: string)
            }

            throw HTTPClientError.responseError(response: httpResponse, detail: "Invalid response")
        }

        return httpResponse
    }
}

/// Represents errors that can occur during API operations.
// wangqi 2025-12-02: Added LocalizedError conformance for proper error message propagation
public enum HTTPClientError: Error, Hashable, Sendable, CustomStringConvertible, LocalizedError {
    /// An error encountered while constructing the request.
    case requestError(String)

    /// An error returned by the HTTP API.
    case responseError(response: HTTPURLResponse, detail: String)

    /// An error encountered while decoding the response.
    case decodingError(response: HTTPURLResponse, detail: String)

    /// An unexpected error.
    case unexpectedError(String)

    public var description: String {
        switch self {
        case .requestError(let detail):
            return "Request error: \(detail)"
        case .responseError(let response, let detail):
            return "Response error (Status \(response.statusCode)): \(detail)"
        case .decodingError(let response, let detail):
            return "Decoding error (Status \(response.statusCode)): \(detail)"
        case .unexpectedError(let detail):
            return "Unexpected error: \(detail)"
        }
    }

    // wangqi 2025-12-02: LocalizedError implementation for proper error.localizedDescription
    public var errorDescription: String? {
        return description
    }
}
