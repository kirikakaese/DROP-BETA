import DROPCore
import DROPGitHub
import Foundation
import UniformTypeIdentifiers

/// GitHub Releases, tags and release assets of one repository at a time.
public protocol ReleaseServicing: Sendable {
    /// The newest GitHub Releases, drafts included.
    func releases(_ slug: RepositorySlug) async throws -> [GitHubRelease]
    /// The GitHub Release for `tag`, draft or published, or `nil` if there is none.
    func release(_ slug: RepositorySlug, tag: String) async throws -> GitHubRelease?
    func tagExists(_ slug: RepositorySlug, tag: String) async throws -> Bool
    func branches(_ slug: RepositorySlug) async throws -> [GitHubBranch]
    func createRelease(_ slug: RepositorySlug, _ fields: ReleaseFields) async throws -> GitHubRelease
    func updateRelease(_ slug: RepositorySlug, id: Int64, _ fields: ReleaseFields) async throws -> GitHubRelease
    func deleteRelease(_ slug: RepositorySlug, id: Int64) async throws
    func deleteTag(_ slug: RepositorySlug, tag: String) async throws
    func deleteAsset(_ slug: RepositorySlug, id: Int64) async throws
    func uploadAsset(_ slug: RepositorySlug, releaseID: Int64, name: String, file: URL) async throws -> GitHubAsset
}

/// `ReleaseServicing` over the REST API.
public struct LiveReleaseService: ReleaseServicing {
    let client: GitHubClient

    public init(client: GitHubClient) {
        self.client = client
    }

    public func releases(_ slug: RepositorySlug) async throws -> [GitHubRelease] {
        try await client.decode([GitHubRelease].self, from: .releases(slug))
    }

    public func release(_ slug: RepositorySlug, tag: String) async throws -> GitHubRelease? {
        do {
            return try await client.decode(GitHubRelease.self, from: .release(slug, tag: tag))
        } catch let error as DROPError where error.code == .notFound {
            // Drafts aren't found by tag; look through the newest releases instead.
            let recent = try await client.decode([GitHubRelease].self, from: .releases(slug, perPage: 100))
            return recent.first { $0.tagName == tag }
        }
    }

    public func tagExists(_ slug: RepositorySlug, tag: String) async throws -> Bool {
        do {
            _ = try await client.send(.tagReference(slug, tag: tag))
            return true
        } catch let error as DROPError where error.code == .notFound {
            return false
        }
    }

    public func branches(_ slug: RepositorySlug) async throws -> [GitHubBranch] {
        try await client.decodeAllPages(GitHubBranch.self, from: .branches(slug), maximumPages: 3)
    }

    public func createRelease(_ slug: RepositorySlug, _ fields: ReleaseFields) async throws -> GitHubRelease {
        try await client.decode(GitHubRelease.self, from: .createRelease(slug, fields))
    }

    public func updateRelease(_ slug: RepositorySlug, id: Int64, _ fields: ReleaseFields) async throws
        -> GitHubRelease
    {
        try await client.decode(GitHubRelease.self, from: .updateRelease(slug, id: id, fields))
    }

    public func deleteRelease(_ slug: RepositorySlug, id: Int64) async throws {
        _ = try await client.send(.deleteRelease(slug, id: id))
    }

    public func deleteTag(_ slug: RepositorySlug, tag: String) async throws {
        _ = try await client.send(.deleteTag(slug, tag: tag))
    }

    public func deleteAsset(_ slug: RepositorySlug, id: Int64) async throws {
        _ = try await client.send(.deleteAsset(slug, id: id))
    }

    public func uploadAsset(_ slug: RepositorySlug, releaseID: Int64, name: String, file: URL) async throws
        -> GitHubAsset
    {
        let contentType = UTType(filenameExtension: file.pathExtension)?.preferredMIMEType ?? "application/octet-stream"
        let request = GitHubRequest.uploadAsset(
            slug, releaseID: releaseID, name: name, file: file, contentType: contentType
        )
        return try await client.decode(GitHubAsset.self, from: request)
    }
}
