import DROPGitHub
import Foundation
import os

/// An `HTTPTransport` that answers from a closure and records every request. No network.
public final class FakeTransport: HTTPTransport, Sendable {
    public typealias Responder = @Sendable (URLRequest) throws -> (status: Int, headers: [String: String], body: Data)

    private let responder: Responder
    private let recorded = OSAllocatedUnfairLock<[URLRequest]>(initialState: [])

    public init(_ responder: @escaping Responder) {
        self.responder = responder
    }

    public var requests: [URLRequest] { recorded.withLock { $0 } }

    public func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        recorded.withLock { $0.append(request) }
        let answer = try responder(request)
        guard let url = request.url,
            let response = HTTPURLResponse(
                url: url, statusCode: answer.status, httpVersion: "HTTP/1.1", headerFields: answer.headers
            )
        else { throw URLError(.badURL) }
        return (answer.body, response)
    }

    /// A JSON body from a string literal.
    public static func json(_ text: String) -> Data { Data(text.utf8) }

    /// The form fields of a recorded `application/x-www-form-urlencoded` request.
    public static func formFields(of request: URLRequest) -> [String: String] {
        guard let body = request.httpBody, let text = String(data: body, encoding: .utf8) else { return [:] }
        var components = URLComponents()
        components.percentEncodedQuery = text
        var fields: [String: String] = [:]
        for item in components.queryItems ?? [] {
            fields[item.name] = item.value
        }
        return fields
    }
}

/// An `AccessTokenProviding` with fixed answers, counting how often a rejected token was replaced.
public actor StaticTokens: AccessTokenProviding {
    private var current: String
    private let replacement: String?
    public private(set) var replacements = 0

    public init(_ token: String, replacement: String? = nil) {
        current = token
        self.replacement = replacement
    }

    public func accessToken() async throws -> String { current }

    public func accessToken(replacingRejected token: String) async throws -> String {
        replacements += 1
        guard let replacement else { throw URLError(.userAuthenticationRequired) }
        current = replacement
        return replacement
    }
}
