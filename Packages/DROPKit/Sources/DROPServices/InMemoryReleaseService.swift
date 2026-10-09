import DROPCore
import DROPGitHub
import Foundation
import os

/// `ReleaseServicing` in memory, for tests and previews. Behaves like GitHub where it matters to
/// DROP: drafts don't create tags, uploads report a SHA-256 digest, and any call can be made to fail.
public final class InMemoryReleaseService: ReleaseServicing, Sendable {
    public struct State: Sendable {
        public var releases: [GitHubRelease] = []
        public var tags: Set<String> = []
        public var branches = [GitHubBranch(name: "main")]
        /// Every write, like `create v1.2.3`, `upload app.zip`, `delete asset 7`.
        public var log: [String] = []
        /// The write whose log line starts with this text fails once.
        public var failingWrite: String?
        /// When `false`, uploads report no digest (like older GitHub assets).
        public var reportsDigests = true
        /// Uploads report this digest instead of the real one, to test verification.
        public var corruptsUploads = false
        var nextID: Int64 = 100
    }

    private let state: OSAllocatedUnfairLock<State>

    public init(releases: [GitHubRelease] = [], tags: Set<String> = []) {
        var initial = State()
        initial.releases = releases
        initial.tags = tags.union(releases.filter { !$0.isDraft }.map(\.tagName))
        state = OSAllocatedUnfairLock(initialState: initial)
    }

    public var snapshot: State { state.withLock { $0 } }

    public func update(_ change: @Sendable (inout State) -> Void) {
        state.withLock { change(&$0) }
    }

    public func releases(_ slug: RepositorySlug) async throws -> [GitHubRelease] {
        state.withLock { $0.releases }.sorted { $0.id > $1.id }
    }

    public func release(_ slug: RepositorySlug, tag: String) async throws -> GitHubRelease? {
        state.withLock { $0.releases.first { $0.tagName == tag } }
    }

    public func tagExists(_ slug: RepositorySlug, tag: String) async throws -> Bool {
        state.withLock { $0.tags.contains(tag) }
    }

    public func branches(_ slug: RepositorySlug) async throws -> [GitHubBranch] {
        state.withLock { $0.branches }
    }

    public func createRelease(_ slug: RepositorySlug, _ fields: ReleaseFields) async throws -> GitHubRelease {
        let tag = fields.tagName ?? ""
        return try write("create \(tag)") { state in
            let release = GitHubRelease(
                id: state.takeID(),
                tagName: tag,
                name: fields.name,
                body: fields.body,
                isDraft: fields.isDraft ?? false,
                isPrerelease: fields.isPrerelease ?? false,
                htmlURL: URL(string: "https://github.com/\(slug)/releases/tag/\(tag)"),
                targetCommitish: fields.targetCommitish
            )
            state.releases.append(release)
            if !release.isDraft { state.tags.insert(tag) }
            return release
        }
    }

    public func updateRelease(_ slug: RepositorySlug, id: Int64, _ fields: ReleaseFields) async throws
        -> GitHubRelease
    {
        try write("update \(id)") { state in
            guard let index = state.releases.firstIndex(where: { $0.id == id }) else { throw Self.notFound }
            let old = state.releases[index]
            let release = GitHubRelease(
                id: id,
                tagName: old.tagName,
                name: fields.name ?? old.name,
                body: fields.body ?? old.body,
                isDraft: fields.isDraft ?? old.isDraft,
                isPrerelease: fields.isPrerelease ?? old.isPrerelease,
                htmlURL: old.htmlURL,
                targetCommitish: old.targetCommitish,
                assets: old.assets
            )
            state.releases[index] = release
            if !release.isDraft { state.tags.insert(release.tagName) }
            return release
        }
    }

    public func deleteRelease(_ slug: RepositorySlug, id: Int64) async throws {
        try write("delete release \(id)") { state in
            guard state.releases.contains(where: { $0.id == id }) else { throw Self.notFound }
            state.releases.removeAll { $0.id == id }
        }
    }

    public func deleteTag(_ slug: RepositorySlug, tag: String) async throws {
        try write("delete tag \(tag)") { state in
            guard state.tags.remove(tag) != nil else { throw Self.notFound }
        }
    }

    public func deleteAsset(_ slug: RepositorySlug, id: Int64) async throws {
        try write("delete asset \(id)") { state in
            guard let index = state.releases.firstIndex(where: { $0.assets.contains { $0.id == id } }) else {
                throw Self.notFound
            }
            state.releases[index] = state.releases[index].replacingAssets { $0.filter { $0.id != id } }
        }
    }

    public func uploadAsset(_ slug: RepositorySlug, releaseID: Int64, name: String, file: URL) async throws
        -> GitHubAsset
    {
        let data = try Data(contentsOf: file)
        return try write("upload \(name)") { state in
            guard let index = state.releases.firstIndex(where: { $0.id == releaseID }) else { throw Self.notFound }
            guard !state.releases[index].assets.contains(where: { $0.name == name }) else {
                throw DROPError(.rejected, whatHappened: "already_exists")
            }
            let sha = state.corruptsUploads ? String(repeating: "0", count: 64) : Checksums.sha256(of: data)
            let asset = GitHubAsset(
                id: state.takeID(),
                name: name,
                size: Int64(data.count),
                digest: state.reportsDigests ? "sha256:\(sha)" : nil
            )
            state.releases[index] = state.releases[index].replacingAssets { $0 + [asset] }
            return asset
        }
    }

    private func write<Value: Sendable>(
        _ line: String,
        _ body: @Sendable (inout State) throws -> Value
    ) throws -> Value {
        try state.withLock { state in
            if let failing = state.failingWrite, line.hasPrefix(failing) {
                state.failingWrite = nil
                throw DROPError.network(details: "Injected failure: \(line)")
            }
            let value = try body(&state)
            state.log.append(line)
            return value
        }
    }

    private static var notFound: DROPError { .repositoryNotFound(details: nil) }
}

extension InMemoryReleaseService.State {
    fileprivate mutating func takeID() -> Int64 {
        nextID += 1
        return nextID
    }
}

extension GitHubRelease {
    fileprivate func replacingAssets(_ change: ([GitHubAsset]) -> [GitHubAsset]) -> GitHubRelease {
        GitHubRelease(
            id: id,
            tagName: tagName,
            name: name,
            body: body,
            isDraft: isDraft,
            isPrerelease: isPrerelease,
            htmlURL: htmlURL,
            targetCommitish: targetCommitish,
            createdAt: createdAt,
            publishedAt: publishedAt,
            assets: change(assets)
        )
    }
}
