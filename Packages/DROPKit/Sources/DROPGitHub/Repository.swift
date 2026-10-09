import DROPCore
import Foundation

/// A tag (`GET /repos/{owner}/{repo}/tags`).
public struct GitHubTag: Decodable, Sendable, Equatable {
    public let name: String
    public let sha: String

    public init(name: String, sha: String) {
        self.name = name
        self.sha = sha
    }

    enum CodingKeys: String, CodingKey { case name, commit }
    enum CommitKeys: String, CodingKey { case sha }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        name = try container.decode(String.self, forKey: .name)
        sha = try container.nestedContainer(keyedBy: CommitKeys.self, forKey: .commit)
            .decode(String.self, forKey: .sha)
    }
}

/// A commit with its full message.
public struct GitHubCommit: Decodable, Sendable, Equatable {
    public let sha: String
    public let message: String

    public init(sha: String, message: String) {
        self.sha = sha
        self.message = message
    }

    enum CodingKeys: String, CodingKey { case sha, commit }
    enum CommitKeys: String, CodingKey { case message }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sha = try container.decode(String.self, forKey: .sha)
        message = try container.nestedContainer(keyedBy: CommitKeys.self, forKey: .commit)
            .decode(String.self, forKey: .message)
    }
}

/// `GET /repos/{owner}/{repo}/compare/{base}...{head}`: the commits on head since base.
public struct GitHubComparison: Decodable, Sendable, Equatable {
    public let totalCommits: Int
    /// Oldest first, at most 250.
    public let commits: [GitHubCommit]

    enum CodingKeys: String, CodingKey {
        case commits
        case totalCommits = "total_commits"
    }
}

/// A file's contents (`GET /repos/{owner}/{repo}/contents/{path}`).
public struct GitHubFile: Decodable, Sendable, Equatable {
    /// The blob SHA, needed to update the file.
    public let sha: String
    public let text: String

    public init(sha: String, text: String) {
        self.sha = sha
        self.text = text
    }

    enum CodingKeys: String, CodingKey { case sha, content, encoding }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sha = try container.decode(String.self, forKey: .sha)
        let encoding = try container.decodeIfPresent(String.self, forKey: .encoding)
        let content = try container.decodeIfPresent(String.self, forKey: .content) ?? ""
        guard encoding == "base64",
            let data = Data(base64Encoded: content, options: .ignoreUnknownCharacters),
            let text = String(data: data, encoding: .utf8)
        else {
            throw DecodingError.dataCorruptedError(
                forKey: .content, in: container, debugDescription: "Not base64-encoded UTF-8 text"
            )
        }
        self.text = text
    }
}

/// The author and committer of a commit DROP makes through the API.
public struct GitHubIdentity: Encodable, Sendable, Equatable {
    public let name: String
    public let email: String

    public init(name: String, email: String) {
        self.name = name
        self.email = email
    }

    /// The account's private `ID+login@users.noreply.github.com` address, so a commit DROP makes
    /// never exposes an email address.
    public init(user: GitHubUser) {
        name = user.login
        email = "\(user.id)+\(user.login)@users.noreply.github.com"
    }
}

/// An opened pull request.
public struct GitHubPullRequest: Decodable, Sendable, Equatable {
    public let number: Int
    public let htmlURL: URL?

    public init(number: Int, htmlURL: URL?) {
        self.number = number
        self.htmlURL = htmlURL
    }

    enum CodingKeys: String, CodingKey {
        case number
        case htmlURL = "html_url"
    }
}

/// The object a ref points at (`GET /repos/{owner}/{repo}/git/ref/heads/{branch}`).
public struct GitHubReference: Decodable, Sendable {
    public struct Object: Decodable, Sendable {
        public let sha: String
    }

    public let object: Object
}

extension GitHubRequest {
    public static func tags(_ slug: RepositorySlug) -> GitHubRequest {
        GitHubRequest(path: repositoryPath(slug) + "/tags", query: [URLQueryItem(name: "per_page", value: "100")])
    }

    public static func compare(_ slug: RepositorySlug, base: String, head: String) -> GitHubRequest {
        GitHubRequest(
            path: repositoryPath(slug) + "/compare/" + encodeSegment(base) + "..." + encodeSegment(head),
            query: [URLQueryItem(name: "per_page", value: "250")]
        )
    }

    /// The newest commits on `branch`, newest first.
    public static func commits(_ slug: RepositorySlug, branch: String) -> GitHubRequest {
        GitHubRequest(path: repositoryPath(slug) + "/commits", query: [
            URLQueryItem(name: "sha", value: branch),
            URLQueryItem(name: "per_page", value: "100"),
        ])
    }

    public static func file(_ slug: RepositorySlug, path: String, ref: String) -> GitHubRequest {
        GitHubRequest(
            path: repositoryPath(slug) + "/contents/" + encodeSegment(path),
            query: [URLQueryItem(name: "ref", value: ref)]
        )
    }

    public static func branchReference(_ slug: RepositorySlug, branch: String) -> GitHubRequest {
        GitHubRequest(path: repositoryPath(slug) + "/git/ref/heads/" + encodeSegment(branch))
    }

    public static func createBranch(_ slug: RepositorySlug, name: String, sha: String) throws -> GitHubRequest {
        try createReference(slug, ref: "refs/heads/\(name)", sha: sha)
    }

    /// A lightweight tag on `sha`. A workflow that starts on tag pushes starts as for a pushed tag.
    public static func createTag(_ slug: RepositorySlug, name: String, sha: String) throws -> GitHubRequest {
        try createReference(slug, ref: "refs/tags/\(name)", sha: sha)
    }

    static func createReference(_ slug: RepositorySlug, ref: String, sha: String) throws -> GitHubRequest {
        let body = try JSONEncoder().encode(["ref": ref, "sha": sha])
        return GitHubRequest(.post, path: repositoryPath(slug) + "/git/refs", body: body)
    }

    /// `GET /repos/{owner}/{repo}/commits/{ref}`: a branch, tag or abbreviated SHA as one commit.
    public static func commit(_ slug: RepositorySlug, ref: String) -> GitHubRequest {
        GitHubRequest(path: repositoryPath(slug) + "/commits/" + encodeSegment(ref))
    }

    /// `PUT /repos/{owner}/{repo}/contents/{path}`: creates or updates one file in one commit.
    public static func putFile(
        _ slug: RepositorySlug,
        path: String,
        change: FileChange
    ) throws -> GitHubRequest {
        GitHubRequest(
            .put,
            path: repositoryPath(slug) + "/contents/" + encodeSegment(path),
            body: try JSONEncoder().encode(change)
        )
    }

    public static func openPullRequest(_ slug: RepositorySlug, _ pullRequest: NewPullRequest) throws
        -> GitHubRequest
    {
        GitHubRequest(.post, path: repositoryPath(slug) + "/pulls", body: try JSONEncoder().encode(pullRequest))
    }
}

/// The body of a file commit through the contents API.
public struct FileChange: Encodable, Sendable, Equatable {
    public let message: String
    public let content: String
    public let branch: String
    /// The current blob SHA when updating; `nil` when creating the file.
    public let sha: String?
    public let author: GitHubIdentity
    public let committer: GitHubIdentity

    public init(message: String, text: String, branch: String, sha: String?, identity: GitHubIdentity) {
        self.message = message
        content = Data(text.utf8).base64EncodedString()
        self.branch = branch
        self.sha = sha
        author = identity
        committer = identity
    }
}

/// The body of a new pull request.
public struct NewPullRequest: Encodable, Sendable, Equatable {
    public let title: String
    public let head: String
    public let base: String
    public let body: String

    public init(title: String, head: String, base: String, body: String) {
        self.title = title
        self.head = head
        self.base = base
        self.body = body
    }
}
