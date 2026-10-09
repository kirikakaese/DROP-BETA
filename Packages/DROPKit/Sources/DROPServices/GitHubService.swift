import DROPCore
import DROPGitHub
import Foundation
import os

/// What DROP reads from GitHub about the account and its repositories.
public protocol GitHubServicing: Sendable {
    func currentUser() async throws -> GitHubUser
    /// Repositories you own or collaborate on, most recently pushed first.
    func yourRepositories() async throws -> [GitHubRepository]
    func repository(_ slug: RepositorySlug) async throws -> GitHubRepository
    /// Finds a repository by GitHub's ID, whatever it is called now.
    func repository(id: Int64) async throws -> GitHubRepository
}

/// `GitHubServicing` over the REST API.
public struct LiveGitHubService: GitHubServicing {
    let client: GitHubClient

    public init(client: GitHubClient) {
        self.client = client
    }

    public func currentUser() async throws -> GitHubUser {
        try await client.decode(GitHubUser.self, from: .currentUser)
    }

    public func yourRepositories() async throws -> [GitHubRepository] {
        try await client.decodeAllPages(GitHubRepository.self, from: .yourRepositories, maximumPages: 5)
    }

    public func repository(_ slug: RepositorySlug) async throws -> GitHubRepository {
        try await client.decode(GitHubRepository.self, from: .repository(slug))
    }

    public func repository(id: Int64) async throws -> GitHubRepository {
        try await client.decode(GitHubRepository.self, from: .repository(id: id))
    }
}

/// `GitHubServicing` in memory, for tests and previews. Repositories can be renamed to see how DROP
/// follows them.
public final class InMemoryGitHubService: GitHubServicing, Sendable {
    private struct State {
        var user: GitHubUser
        var repositories: [GitHubRepository]
        var error: DROPError?
    }

    private let state: OSAllocatedUnfairLock<State>

    public init(user: GitHubUser = GitHubUser(id: 1, login: "octocat"), repositories: [GitHubRepository] = []) {
        state = OSAllocatedUnfairLock(initialState: State(user: user, repositories: repositories))
    }

    /// Every call throws `error` until it is set back to `nil`.
    public func setError(_ error: DROPError?) {
        state.withLock { $0.error = error }
    }

    public func rename(id: Int64, to fullName: String) {
        state.withLock { state in
            guard let index = state.repositories.firstIndex(where: { $0.id == id }) else { return }
            let old = state.repositories[index]
            state.repositories[index] = GitHubRepository(
                id: old.id,
                fullName: fullName,
                isPrivate: old.isPrivate,
                isArchived: old.isArchived,
                defaultBranch: old.defaultBranch,
                summary: old.summary,
                pushedAt: old.pushedAt
            )
        }
    }

    public func currentUser() async throws -> GitHubUser {
        try read { $0.user }
    }

    public func yourRepositories() async throws -> [GitHubRepository] {
        try read { $0.repositories }
    }

    public func repository(_ slug: RepositorySlug) async throws -> GitHubRepository {
        try read { $0.repositories.first { $0.slug == slug } }
    }

    public func repository(id: Int64) async throws -> GitHubRepository {
        try read { $0.repositories.first { $0.id == id } }
    }

    private func read<Value: Sendable>(_ body: @Sendable (State) -> Value?) throws -> Value {
        let (value, error) = state.withLock { (body($0), $0.error) }
        if let error { throw error }
        guard let value else {
            throw DROPError.repositoryNotFound(details: nil)
        }
        return value
    }
}
