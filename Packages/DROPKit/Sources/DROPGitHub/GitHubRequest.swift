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

    /// The two hosts the REST API uses. Release assets are uploaded to `uploads.github.com`.
    public enum Host: String, Sendable {
        case api = "api.github.com"
        case uploads = "uploads.github.com"
    }

    /// The REST API version DROP is written against.
    public static let apiVersion = "2022-11-28"
    public static let apiBaseURL = URL(string: "https://api.github.com")

    public var method: Method
    public var host: Host
    /// The path below the API root, starting with `/`, for example `/repos/owner/name/releases`.
    public var path: String
    public var query: [URLQueryItem]
    public var body: Data?
    /// A file sent as the body instead of `body`, streamed from disk (release assets).
    public var uploadFile: URL?
    /// The body's media type; JSON unless set.
    public var contentType: String?

    public init(
        _ method: Method = .get,
        host: Host = .api,
        path: String,
        query: [URLQueryItem] = [],
        body: Data? = nil,
        uploadFile: URL? = nil,
        contentType: String? = nil
    ) {
        self.method = method
        self.host = host
        self.path = path
        self.query = query
        self.body = body
        self.uploadFile = uploadFile
        self.contentType = contentType
    }

    /// The request to send. The access token is added here and nowhere else; pass `nil` for
    /// calls that don't need one.
    public func urlRequest(token: String?, userAgent: String) throws -> URLRequest {
        guard path.hasPrefix("/"), !path.hasPrefix("//"), !path.contains("://") else {
            throw Self.invalidRequest
        }
        var components = URLComponents()
        components.scheme = "https"
        components.host = host.rawValue
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
        if uploadFile != nil {
            request.setValue(contentType ?? "application/octet-stream", forHTTPHeaderField: "Content-Type")
        } else if body != nil {
            request.setValue(contentType ?? "application/json", forHTTPHeaderField: "Content-Type")
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
        GitHubRequest(path: repositoryPath(slug))
    }

    /// `/repos/{owner}/{repo}`. Owner and name are validated to URL-safe characters.
    static func repositoryPath(_ slug: RepositorySlug) -> String {
        "/repos/\(slug.owner)/\(slug.name)"
    }

    /// Percent-encodes one path segment (a tag name), keeping `/` for tags like `app/v1.0`.
    static func encodeSegment(_ text: String) -> String {
        var allowed = CharacterSet.urlPathAllowed
        allowed.remove(charactersIn: "?#%;")
        return text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
}
