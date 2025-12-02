// wangqi 2025-12-02: Middleware protocol for debugging/inspection support

import Foundation

#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Protocol for intercepting HuggingFace API HTTP requests and responses
/// Used for debugging and logging API calls
public protocol HuggingFaceMiddleware: Sendable {
    /// Intercepts outgoing HTTP requests before they are sent
    /// - Parameter request: The URLRequest about to be sent
    /// - Returns: The (possibly modified) request to send
    func intercept(request: URLRequest) -> URLRequest

    /// Intercepts streaming data chunks during SSE streaming
    /// - Parameters:
    ///   - request: The original request (if available)
    ///   - data: The data chunk received
    /// - Returns: The (possibly modified) data
    func interceptStreamingData(request: URLRequest?, _ data: Data) -> Data

    /// Intercepts streaming lines (SSE events) during streaming
    /// - Parameters:
    ///   - request: The original request (if available)
    ///   - line: The SSE line received
    /// - Returns: The (possibly modified) line
    func interceptStreamingLine(request: URLRequest?, _ line: String) -> String

    /// Intercepts complete HTTP responses after they are received
    /// - Parameters:
    ///   - response: The HTTP response received
    ///   - request: The original request
    ///   - data: The response data
    /// - Returns: Tuple of (possibly modified) response and data
    func intercept(response: HTTPURLResponse?, request: URLRequest, data: Data?) -> (response: HTTPURLResponse?, data: Data?)

    /// Intercepts errors that occur during requests
    /// - Parameters:
    ///   - response: The HTTP response (if available)
    ///   - request: The original request (if available)
    ///   - data: Any response data (if available)
    ///   - error: The error that occurred
    func interceptError(response: HTTPURLResponse?, request: URLRequest?, data: Data?, error: Error?)
}

/// Default implementation for optional methods
public extension HuggingFaceMiddleware {
    func interceptStreamingData(request: URLRequest?, _ data: Data) -> Data { data }
    func interceptStreamingLine(request: URLRequest?, _ line: String) -> String { line }
    func interceptError(response: HTTPURLResponse?, request: URLRequest?, data: Data?, error: Error?) {}
}
