import DROPCore
import DROPGitHub
import Foundation
import os

/// Tags, history and files of a repository, and the writes a changelog pull request needs.
public protocol RepositoryServicing: Sendable {
    func tags(_ slug: RepositorySlug) async throws -> [GitHubTag]
    /// Commits on `head` since `base`, oldest first.
    func commits(_ slug: RepositorySlug, since base: String, head: String) async throws -> [GitHubCommit]
    /// The newest commits on `branch`, oldest first (for repositories without tags).
    func recentCommits(_ slug: RepositorySlug, branch: String) async throws -> [GitHubCommit]
    /// The file on `ref`, or `nil` if it doesn't exist.
    func file(_ slug: RepositorySlug, path: String, ref: String) async throws -> GitHubFile?
    func branchHead(_ slug: RepositorySlug, branch: String) async throws -> String
    func createBranch(_ slug: RepositorySlug, name: String, from sha: String) async throws
    /// The full SHA of a branch, tag or abbreviated SHA.
    func commitSHA(_ slug: RepositorySlug, ref: String) async throws -> String
    /// Creates the tag `name` on `sha` (and so pushes it).
    func createTag(_ slug: RepositorySlug, name: String, sha: String) async throws
    func putFile(_ slug: RepositorySlug, path: String, change: FileChange) async throws
    func openPullRequest(_ slug: RepositorySlug, _ pullRequest: NewPullRequest) async throws -> GitHubPullRequest
}

/// `RepositoryServicing` over the REST API.
public struct LiveRepositoryService: RepositoryServicing {
    let client: GitHubClient

    public init(client: GitHubClient) {
        self.client = client
    }

    public func tags(_ slug: RepositorySlug) async throws -> [GitHubTag] {
        try await client.decodeAllPages(GitHubTag.self, from: .tags(slug), maximumPages: 3)
    }

    public func commits(_ slug: RepositorySlug, since base: String, head: String) async throws -> [GitHubCommit] {
        try await client.decode(GitHubComparison.self, from: .compare(slug, base: base, head: head)).commits
    }

    public func recentCommits(_ slug: RepositorySlug, branch: String) async throws -> [GitHubCommit] {
        try await client.decode([GitHubCommit].self, from: .commits(slug, branch: branch)).reversed()
    }

    public func file(_ slug: RepositorySlug, path: String, ref: String) async throws -> GitHubFile? {
        do {
            return try await client.decode(GitHubFile.self, from: .file(slug, path: path, ref: ref))
        } catch let error as DROPError where error.code == .notFound {
            return nil
        }
    }

    public func branchHead(_ slug: RepositorySlug, branch: String) async throws -> String {
        try await client.decode(GitHubReference.self, from: .branchReference(slug, branch: branch)).object.sha
    }

    public func createBranch(_ slug: RepositorySlug, name: String, from sha: String) async throws {
        _ = try await client.send(.createBranch(slug, name: name, sha: sha))
    }

    public func commitSHA(_ slug: RepositorySlug, ref: String) async throws -> String {
        try await client.decode(GitHubCommit.self, from: .commit(slug, ref: ref)).sha
    }

    public func createTag(_ slug: RepositorySlug, name: String, sha: String) async throws {
        _ = try await client.send(.createTag(slug, name: name, sha: sha))
    }

    public func putFile(_ slug: RepositorySlug, path: String, change: FileChange) async throws {
        _ = try await client.send(.putFile(slug, path: path, change: change))
    }

    public func openPullRequest(_ slug: RepositorySlug, _ pullRequest: NewPullRequest) async throws
        -> GitHubPullRequest
    {
        try await client.decode(GitHubPullRequest.self, from: .openPullRequest(slug, pullRequest))
    }
}

/// `RepositoryServicing` in memory, for tests and previews: one branch history with tags on it.
public final class InMemoryRepositoryService: RepositoryServicing, Sendable {
    public struct State: Sendable {
        /// Commits on the default branch, oldest first.
        public var commits: [GitHubCommit] = []
        /// Tag name → commit SHA.
        public var tags: [String: String] = [:]
        /// Files by branch, then path.
        public var files: [String: [String: String]] = [:]
        public var branches: [String: String] = [:]
        public var pullRequests: [NewPullRequest] = []
        /// Every file commit, for checking messages and identities.
        public var fileChanges: [FileChange] = []
    }

    private let state: OSAllocatedUnfairLock<State>

    public init(commits: [GitHubCommit] = [], tags: [String: String] = [:], files: [String: String] = [:]) {
        var initial = State()
        initial.commits = commits
        initial.tags = tags
        initial.files = ["main": files]
        initial.branches = ["main": commits.last?.sha ?? "0000000"]
        state = OSAllocatedUnfairLock(initialState: initial)
    }

    public var snapshot: State { state.withLock { $0 } }

    public func tags(_ slug: RepositorySlug) async throws -> [GitHubTag] {
        state.withLock { $0.tags.map { GitHubTag(name: $0.key, sha: $0.value) } }
    }

    public func commits(_ slug: RepositorySlug, since base: String, head: String) async throws -> [GitHubCommit] {
        try state.withLock { state in
            guard let baseSHA = state.tags[base] ?? state.commits.first(where: { $0.sha == base })?.sha,
                let index = state.commits.firstIndex(where: { $0.sha == baseSHA })
            else { throw DROPError.repositoryNotFound(details: "No such base \(base)") }
            return Array(state.commits[(index + 1)...])
        }
    }

    public func recentCommits(_ slug: RepositorySlug, branch: String) async throws -> [GitHubCommit] {
        state.withLock { $0.commits }
    }

    public func file(_ slug: RepositorySlug, path: String, ref: String) async throws -> GitHubFile? {
        state.withLock { state in
            state.files[ref]?[path].map { GitHubFile(sha: "blob-\($0.count)", text: $0) }
        }
    }

    public func branchHead(_ slug: RepositorySlug, branch: String) async throws -> String {
        try state.withLock { state in
            guard let sha = state.branches[branch] else { throw DROPError.repositoryNotFound(details: branch) }
            return sha
        }
    }

    public func createBranch(_ slug: RepositorySlug, name: String, from sha: String) async throws {
        try state.withLock { state in
            guard state.branches[name] == nil else {
                throw DROPError(.rejected, whatHappened: "Reference already exists")
            }
            state.branches[name] = sha
            state.files[name] = state.files["main"] ?? [:]
        }
    }

    public func commitSHA(_ slug: RepositorySlug, ref: String) async throws -> String {
        try state.withLock { state in
            if let sha = state.branches[ref] ?? state.tags[ref] { return sha }
            guard let commit = state.commits.first(where: { $0.sha.hasPrefix(ref) }) else {
                throw DROPError.repositoryNotFound(details: "No commit \(ref)")
            }
            return commit.sha
        }
    }

    public func createTag(_ slug: RepositorySlug, name: String, sha: String) async throws {
        try state.withLock { state in
            guard state.tags[name] == nil else { throw DROPError(.rejected, whatHappened: "Reference already exists") }
            state.tags[name] = sha
        }
    }

    public func putFile(_ slug: RepositorySlug, path: String, change: FileChange) async throws {
        state.withLock { state in
            let text = Data(base64Encoded: change.content).flatMap { String(data: $0, encoding: .utf8) } ?? ""
            state.files[change.branch, default: [:]][path] = text
            state.fileChanges.append(change)
        }
    }

    public func openPullRequest(_ slug: RepositorySlug, _ pullRequest: NewPullRequest) async throws
        -> GitHubPullRequest
    {
        state.withLock { state in
            state.pullRequests.append(pullRequest)
            let number = state.pullRequests.count
            return GitHubPullRequest(number: number, htmlURL: URL(string: "https://github.com/\(slug)/pull/\(number)"))
        }
    }
}
