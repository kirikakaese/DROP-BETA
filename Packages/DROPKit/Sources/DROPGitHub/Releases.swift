import DROPCore
import Foundation

/// A GitHub Release (`GET /repos/{owner}/{repo}/releases`).
public struct GitHubRelease: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int64
    public let tagName: String
    public let name: String?
    public let body: String?
    public let isDraft: Bool
    public let isPrerelease: Bool
    public let htmlURL: URL?
    public let targetCommitish: String?
    public let createdAt: Date?
    public let publishedAt: Date?
    public let assets: [GitHubAsset]

    public init(
        id: Int64,
        tagName: String,
        name: String? = nil,
        body: String? = nil,
        isDraft: Bool = false,
        isPrerelease: Bool = false,
        htmlURL: URL? = nil,
        targetCommitish: String? = nil,
        createdAt: Date? = nil,
        publishedAt: Date? = nil,
        assets: [GitHubAsset] = []
    ) {
        self.id = id
        self.tagName = tagName
        self.name = name
        self.body = body
        self.isDraft = isDraft
        self.isPrerelease = isPrerelease
        self.htmlURL = htmlURL
        self.targetCommitish = targetCommitish
        self.createdAt = createdAt
        self.publishedAt = publishedAt
        self.assets = assets
    }

    /// The title GitHub shows: the name, or the tag when the name is empty.
    public var title: String {
        guard let name, !name.isEmpty else { return tagName }
        return name
    }

    enum CodingKeys: String, CodingKey {
        case id, name, body, assets
        case tagName = "tag_name"
        case isDraft = "draft"
        case isPrerelease = "prerelease"
        case htmlURL = "html_url"
        case targetCommitish = "target_commitish"
        case createdAt = "created_at"
        case publishedAt = "published_at"
    }
}

/// A file attached to a GitHub Release.
public struct GitHubAsset: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int64
    public let name: String
    public let size: Int64
    /// GitHub's checksum of the uploaded file, like `sha256:…`. Missing on older assets.
    public let digest: String?
    public let state: String?
    public let downloadURL: URL?

    public init(id: Int64, name: String, size: Int64, digest: String? = nil, state: String? = "uploaded") {
        self.id = id
        self.name = name
        self.size = size
        self.digest = digest
        self.state = state
        downloadURL = nil
    }

    /// The SHA-256 from `digest` as lowercase hex, if GitHub reported one.
    public var sha256: String? {
        guard let digest, digest.lowercased().hasPrefix("sha256:") else { return nil }
        return String(digest.dropFirst("sha256:".count)).lowercased()
    }

    enum CodingKeys: String, CodingKey {
        case id, name, size, digest, state
        case downloadURL = "browser_download_url"
    }
}

/// A branch, for picking where a new tag points.
public struct GitHubBranch: Decodable, Sendable, Equatable, Identifiable {
    public var id: String { name }
    public let name: String

    public init(name: String) {
        self.name = name
    }
}

/// The fields DROP sets when creating or editing a GitHub Release. `nil` fields are left out.
public struct ReleaseFields: Encodable, Sendable, Equatable {
    public var tagName: String?
    public var targetCommitish: String?
    public var name: String?
    public var body: String?
    public var isDraft: Bool?
    public var isPrerelease: Bool?

    public init(
        tagName: String? = nil,
        targetCommitish: String? = nil,
        name: String? = nil,
        body: String? = nil,
        isDraft: Bool? = nil,
        isPrerelease: Bool? = nil
    ) {
        self.tagName = tagName
        self.targetCommitish = targetCommitish
        self.name = name
        self.body = body
        self.isDraft = isDraft
        self.isPrerelease = isPrerelease
    }

    enum CodingKeys: String, CodingKey {
        case name, body
        case tagName = "tag_name"
        case targetCommitish = "target_commitish"
        case isDraft = "draft"
        case isPrerelease = "prerelease"
    }
}

extension GitHubRequest {
    /// `GET /repos/{owner}/{repo}/releases`, newest first. Includes drafts when you can push.
    public static func releases(_ slug: RepositorySlug, perPage: Int = 30) -> GitHubRequest {
        GitHubRequest(path: repositoryPath(slug) + "/releases", query: [
            URLQueryItem(name: "per_page", value: String(perPage)),
        ])
    }

    /// `GET /repos/{owner}/{repo}/releases/tags/{tag}`. Published releases only; GitHub answers 404
    /// for drafts, so drafts are matched from `releases(_:)` instead.
    public static func release(_ slug: RepositorySlug, tag: String) -> GitHubRequest {
        GitHubRequest(path: repositoryPath(slug) + "/releases/tags/" + encodeSegment(tag))
    }

    /// `GET /repos/{owner}/{repo}/git/ref/tags/{tag}`: whether the tag exists.
    public static func tagReference(_ slug: RepositorySlug, tag: String) -> GitHubRequest {
        GitHubRequest(path: repositoryPath(slug) + "/git/ref/tags/" + encodeSegment(tag))
    }

    /// `GET /repos/{owner}/{repo}/branches`.
    public static func branches(_ slug: RepositorySlug) -> GitHubRequest {
        GitHubRequest(path: repositoryPath(slug) + "/branches", query: [
            URLQueryItem(name: "per_page", value: "100"),
        ])
    }

    /// `POST /repos/{owner}/{repo}/releases`. Creates the tag too when it doesn't exist yet.
    public static func createRelease(_ slug: RepositorySlug, _ fields: ReleaseFields) throws -> GitHubRequest {
        GitHubRequest(.post, path: repositoryPath(slug) + "/releases", body: try JSONEncoder().encode(fields))
    }

    /// `PATCH /repos/{owner}/{repo}/releases/{id}`.
    public static func updateRelease(_ slug: RepositorySlug, id: Int64, _ fields: ReleaseFields) throws
        -> GitHubRequest
    {
        GitHubRequest(.patch, path: repositoryPath(slug) + "/releases/\(id)", body: try JSONEncoder().encode(fields))
    }

    /// `DELETE /repos/{owner}/{repo}/releases/{id}`. Leaves the tag.
    public static func deleteRelease(_ slug: RepositorySlug, id: Int64) -> GitHubRequest {
        GitHubRequest(.delete, path: repositoryPath(slug) + "/releases/\(id)")
    }

    /// `DELETE /repos/{owner}/{repo}/git/refs/tags/{tag}`.
    public static func deleteTag(_ slug: RepositorySlug, tag: String) -> GitHubRequest {
        GitHubRequest(.delete, path: repositoryPath(slug) + "/git/refs/tags/" + encodeSegment(tag))
    }

    /// `DELETE /repos/{owner}/{repo}/releases/assets/{id}`.
    public static func deleteAsset(_ slug: RepositorySlug, id: Int64) -> GitHubRequest {
        GitHubRequest(.delete, path: repositoryPath(slug) + "/releases/assets/\(id)")
    }

    /// `POST https://uploads.github.com/repos/{owner}/{repo}/releases/{id}/assets?name=…`, with the
    /// file streamed from disk.
    public static func uploadAsset(
        _ slug: RepositorySlug,
        releaseID: Int64,
        name: String,
        file: URL,
        contentType: String
    ) -> GitHubRequest {
        GitHubRequest(
            .post,
            host: .uploads,
            path: repositoryPath(slug) + "/releases/\(releaseID)/assets",
            query: [URLQueryItem(name: "name", value: name)],
            uploadFile: file,
            contentType: contentType
        )
    }
}
