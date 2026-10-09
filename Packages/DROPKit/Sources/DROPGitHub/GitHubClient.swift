import DROPCore
import Foundation

/// Hands out access tokens. Implemented by the auth service, which refreshes tokens as needed.
public protocol AccessTokenProviding: Sendable {
    /// A token that is valid for a while yet.
    func accessToken() async throws -> String
    /// A token to retry with after GitHub rejected `token` with 401.
    func accessToken(replacingRejected token: String) async throws -> String
}

/// Sends `GitHubRequest`s with a token, retries once with a fresh token after a 401, and maps
/// GitHub's error responses to `DROPError`.
public struct GitHubClient: Sendable {
    let transport: any HTTPTransport
    let tokens: any AccessTokenProviding
    let userAgent: String

    public init(transport: any HTTPTransport, tokens: any AccessTokenProviding, userAgent: String) {
        self.transport = transport
        self.tokens = tokens
        self.userAgent = userAgent
    }

    /// Sends the request and returns the body of a successful (2xx) response.
    public func send(_ request: GitHubRequest) async throws -> GitHubResponse {
        var token = try await tokens.accessToken()
        var (data, response) = try await transport.send(request.urlRequest(token: token, userAgent: userAgent))
        if response.statusCode == 401 {
            token = try await tokens.accessToken(replacingRejected: token)
            (data, response) = try await transport.send(request.urlRequest(token: token, userAgent: userAgent))
        }
        try Self.check(response, data: data)
        return GitHubResponse(data: data, response: response)
    }

    /// Sends the request and decodes the JSON body.
    public func decode<Value: Decodable>(_ type: Value.Type, from request: GitHubRequest) async throws -> Value {
        try await send(request).decode(type)
    }

    /// Follows `Link: rel="next"` up to `maximumPages` pages and concatenates the results.
    public func decodeAllPages<Element: Decodable>(
        _ type: Element.Type,
        from request: GitHubRequest,
        maximumPages: Int = 10
    ) async throws -> [Element] {
        var elements: [Element] = []
        var next: GitHubRequest? = request
        var pages = 0
        while let current = next, pages < maximumPages {
            let response = try await send(current)
            elements += try response.decode([Element].self)
            next = response.nextPage
            pages += 1
        }
        return elements
    }

    static func check(_ response: HTTPURLResponse, data: Data) throws {
        let status = response.statusCode
        guard !(200..<300).contains(status) else { return }
        let message = GitHubErrorBody.message(in: data)
        switch status {
        case 401:
            throw DROPError.sessionExpired
        case 403 where response.value(forHTTPHeaderField: "x-ratelimit-remaining") == "0", 429:
            throw DROPError(
                .rateLimited,
                whatHappened: String(localized: "GitHub's rate limit for your account is used up."),
                howToFix: String(localized: "Wait a few minutes and try again."),
                details: message
            )
        case 404:
            throw DROPError.repositoryNotFound(details: message)
        case 500...:
            throw DROPError.network(details: "HTTP \(status): \(message ?? "")")
        default:
            throw DROPError(
                .rejected,
                whatHappened: String(localized: "GitHub refused the request (HTTP \(status))."),
                details: message
            )
        }
    }
}

/// A successful response.
public struct GitHubResponse: Sendable {
    public let data: Data
    public let statusCode: Int
    /// The next page from the `Link` header, if there is one on api.github.com.
    public let nextPage: GitHubRequest?

    init(data: Data, response: HTTPURLResponse) {
        self.data = data
        statusCode = response.statusCode
        nextPage = response.value(forHTTPHeaderField: "Link").flatMap(Self.nextPage(inLinkHeader:))
    }

    public func decode<Value: Decodable>(_ type: Value.Type) throws -> Value {
        do {
            return try GitHubJSON.decoder.decode(type, from: data)
        } catch {
            throw DROPError(
                .rejected,
                whatHappened: String(localized: "GitHub sent an answer DROP doesn't understand."),
                details: String(describing: error)
            )
        }
    }

    /// Parses `<https://api.github.com/…?page=2>; rel="next", <…>; rel="last"`.
    static func nextPage(inLinkHeader header: String) -> GitHubRequest? {
        for part in header.split(separator: ",") {
            let pieces = part.split(separator: ";").map { $0.trimmingCharacters(in: .whitespaces) }
            guard pieces.count >= 2, pieces.dropFirst().contains(#"rel="next""#),
                pieces[0].hasPrefix("<"), pieces[0].hasSuffix(">"),
                let components = URLComponents(string: String(pieces[0].dropFirst().dropLast())),
                components.scheme == "https", components.host == GitHubRequest.apiBaseURL?.host()
            else { continue }
            return GitHubRequest(path: components.percentEncodedPath, query: components.queryItems ?? [])
        }
        return nil
    }
}

extension DROPError {
    public static func repositoryNotFound(details: String?) -> DROPError {
        DROPError(
            .notFound,
            whatHappened: String(localized: "GitHub couldn't find that repository, or your account can't see it."),
            details: details
        )
    }
}

enum GitHubJSON {
    static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

private struct GitHubErrorBody: Decodable {
    let message: String?

    static func message(in data: Data) -> String? {
        (try? JSONDecoder().decode(GitHubErrorBody.self, from: data))?.message
    }
}
