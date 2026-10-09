import DROPCore
import Foundation

/// One call to the GitHub REST API, independent of how it is sent.
///
/// Building the `URLRequest` is kept separate from sending it, so the headers every request needs
/// are set in one place and can be tested without a network.
public struct GitHubRequest: Sendable, Equatable {
    public enum Method: String, Sendable {
        case get = "GET"
        case post = "POST"
        case patch = "PATCH"
        case put = "PUT"
        case delete = "DELETE"
    }

    /// The REST API version DROP is written against.
    public static let apiVersion = "2022-11-28"
    public static let apiBaseURL = URL(string: "https://api.github.com")

    public var method: Method
    /// The path below the API root, starting with `/`, for example `/repos/owner/name/releases`.
    public var path: String
    public var query: [URLQueryItem]
    public var body: Data?

    public init(_ method: Method = .get, path: String, query: [URLQueryItem] = [], body: Data? = nil) {
        self.method = method
        self.path = path
        self.query = query
        self.body = body
    }

    /// The request to send. The access token is added here and nowhere else; pass `nil` for
    /// calls that don't need one.
    public func urlRequest(token: String?, userAgent: String) throws -> URLRequest {
        guard path.hasPrefix("/"), !path.hasPrefix("//"), !path.contains("://"), let base = Self.apiBaseURL,
            var components = URLComponents(url: base, resolvingAgainstBaseURL: false)
        else {
            throw Self.invalidRequest
        }
        components.percentEncodedPath = path
        components.queryItems = query.isEmpty ? nil : query
        guard let url = components.url else {
            throw Self.invalidRequest
        }
        var request = URLRequest(url: url)
        request.httpMethod = method.rawValue
        request.httpBody = body
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue(Self.apiVersion, forHTTPHeaderField: "X-GitHub-Api-Version")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        if body != nil {
            request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        }
        if let token {
            request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
        }
        return request
    }

    private static var invalidRequest: DROPError {
        DROPError(.invalidArgument, whatHappened: String(localized: "DROP built an invalid GitHub request."))
    }
}

extension GitHubRequest {
    /// `GET /repos/{owner}/{repo}`.
    public static func repository(_ slug: RepositorySlug) -> GitHubRequest {
        GitHubRequest(path: "/repos/\(slug.owner)/\(slug.name)")
    }
}
