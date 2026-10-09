import DROPCore
import Foundation

/// Sends HTTP requests. The live implementation uses `URLSession`; tests use a fake, so no test
/// ever touches the network.
public protocol HTTPTransport: Sendable {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse)
    /// Sends `request` with the file's contents as the body, streamed from disk.
    func upload(_ request: URLRequest, fromFile file: URL) async throws -> (Data, HTTPURLResponse)
}

/// `HTTPTransport` over an ephemeral `URLSession`: no cookies, no cache, HTTPS only, and redirects
/// only within the same host (GitHub answers renamed repositories with one).
public struct URLSessionTransport: HTTPTransport {
    /// Responses larger than this are refused.
    public static let maximumResponseSize = 10 * 1024 * 1024

    private let session: URLSession

    public init() {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.httpShouldSetCookies = false
        configuration.urlCache = nil
        configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
        configuration.timeoutIntervalForRequest = 30
        session = URLSession(configuration: configuration, delegate: SameHostRedirects(), delegateQueue: nil)
    }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        try await perform(request) { try await session.data(for: request) }
    }

    public func upload(_ request: URLRequest, fromFile file: URL) async throws -> (Data, HTTPURLResponse) {
        try await perform(request) { try await session.upload(for: request, fromFile: file) }
    }

    private func perform(
        _ request: URLRequest,
        _ operation: () async throws -> (Data, URLResponse)
    ) async throws -> (Data, HTTPURLResponse) {
        guard request.url?.scheme == "https" else {
            throw DROPError(.invalidArgument, whatHappened: String(localized: "DROP built an invalid GitHub request."))
        }
        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await operation()
        } catch let error as URLError {
            if error.code == .cancelled { throw CancellationError() }
            throw DROPError.network(details: error.localizedDescription)
        }
        guard let http = response as? HTTPURLResponse else {
            throw DROPError.network(details: "Not an HTTP response")
        }
        guard data.count <= Self.maximumResponseSize else {
            throw DROPError.network(details: "Response too large (\(data.count) bytes)")
        }
        return (data, http)
    }
}

/// Follows redirects only to the same host over HTTPS, and keeps the Authorization header on them.
private final class SameHostRedirects: NSObject, URLSessionTaskDelegate, Sendable {
    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest
    ) async -> URLRequest? {
        guard let original = task.originalRequest, let host = original.url?.host(),
            request.url?.host() == host, request.url?.scheme == "https"
        else { return nil }
        var redirected = request
        if let authorization = original.value(forHTTPHeaderField: "Authorization") {
            redirected.setValue(authorization, forHTTPHeaderField: "Authorization")
        }
        return redirected
    }
}
