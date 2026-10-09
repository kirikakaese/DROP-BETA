import DROPCore
import DROPGitHub
import Foundation

/// What changed on a branch since the last release, and what DROP suggests dropping next.
public struct UnreleasedChanges: Sendable, Equatable {
    /// The tag the changes are counted from: the newest release, or `nil` if there is none yet.
    public let since: String?
    public let commits: [ConventionalCommit]
    public let suggestion: VersionSuggestion

    /// Commits that end up in the notes (no merges, no chores).
    public var notableCount: Int {
        commits.filter { !$0.isMerge && !Changelog.hiddenTypes.contains($0.type ?? "") }.count
    }

    public func count(ofType type: String) -> Int {
        commits.filter { $0.type == type && !$0.isBreaking }.count
    }

    public var breakingCount: Int { commits.filter(\.isBreaking).count }
}

/// Reads Conventional Commits since the last release, suggests the next version and writes the
/// notes, and updates CHANGELOG.md through a pull request (never a push to the default branch).
public struct ChangelogService: Sendable {
    public static let fileName = "CHANGELOG.md"

    let repository: any RepositoryServicing
    let github: any GitHubServicing
    let now: @Sendable () -> Date

    public init(
        repository: any RepositoryServicing,
        github: any GitHubServicing,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.repository = repository
        self.github = github
        self.now = now
    }

    public func unreleased(_ slug: RepositorySlug, branch: String) async throws -> UnreleasedChanges {
        let tags = try await repository.tags(slug).map(\.name)
        let latest = VersionSuggestion(tags: tags, commits: []).latestRelease
        let raw: [GitHubCommit]
        if let latest {
            raw = try await repository.commits(slug, since: latest, head: branch)
        } else {
            raw = try await repository.recentCommits(slug, branch: branch)
        }
        let commits = raw.map { ConventionalCommit(sha: $0.sha, message: $0.message) }
        let suggestion = VersionSuggestion(tags: tags, commits: commits)
        return UnreleasedChanges(since: latest, commits: commits, suggestion: suggestion)
    }

    /// Release notes for `tag` from the unreleased changes.
    public func notes(
        _ changes: UnreleasedChanges,
        slug: RepositorySlug,
        tag: String,
        headingLevel: Int = 2
    ) -> String {
        Changelog.notes(
            for: changes.commits, slug: slug, previousTag: changes.since, newTag: tag, headingLevel: headingLevel
        )
    }

    /// Opens a pull request against `base` that adds `notes` for `tag` to CHANGELOG.md. The commit is
    /// made as the signed-in account with its private noreply address and a Conventional Commit
    /// message, without any trailer.
    public func openPullRequest(
        _ slug: RepositorySlug,
        base: String,
        tag: String,
        notes: String
    ) async throws -> GitHubPullRequest {
        let identity = GitHubIdentity(user: try await github.currentUser())
        let branch = "changelog/\(tag)"
        let head = try await repository.branchHead(slug, branch: base)
        try await repository.createBranch(slug, name: branch, from: head)
        let existing = try await repository.file(slug, path: Self.fileName, ref: branch)
        let text = Changelog.updatingFile(existing?.text, version: tag, date: now(), notes: notes)
        let message = "docs(changelog): add \(tag)"
        try await repository.putFile(slug, path: Self.fileName, change: FileChange(
            message: message, text: text, branch: branch, sha: existing?.sha, identity: identity
        ))
        return try await repository.openPullRequest(slug, NewPullRequest(
            title: message,
            head: branch,
            base: base,
            body: "Adds the notes for \(tag) to \(Self.fileName).\n"
        ))
    }
}
