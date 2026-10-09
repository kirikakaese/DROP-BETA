import DROPCore
import DROPGitHub
import DROPPersistence
import DROPTestFixtures
import Foundation
import Testing

@testable import DROPServices

@Suite("ChangelogService")
struct ChangelogServiceTests {
    let slug = Fixtures.slug("octocat/Hello-World")
    let github = InMemoryGitHubService(user: GitHubUser(id: 252_577_764, login: "kirikakaese"))

    static func history() -> InMemoryRepositoryService {
        InMemoryRepositoryService(
            commits: [
                GitHubCommit(sha: "c1", message: "chore: scaffold the app"),
                GitHubCommit(sha: "c2", message: "feat(auth): sign in with github (#2)"),
                GitHubCommit(sha: "c3", message: "fix(ui): keep the selection (#4)"),
                GitHubCommit(sha: "c4", message: "feat(github): drop a version (#3)"),
            ],
            tags: ["v0.1.0": "c2"],
            files: ["CHANGELOG.md": "# Changelog\n\n## v0.1.0 - 2026-10-01\n\n### Features\n\n- first\n"]
        )
    }

    var service: (ChangelogService, InMemoryRepositoryService) {
        let repository = Self.history()
        return (
            ChangelogService(repository: repository, github: github, now: { Fixtures.referenceDate }),
            repository
        )
    }

    @Test func findsTheCommitsSinceTheLastReleaseAndSuggestsTheNextVersion() async throws {
        let (changelog, _) = service
        let changes = try await changelog.unreleased(slug, branch: "main")
        #expect(changes.since == "v0.1.0")
        #expect(changes.commits.map(\.sha) == ["c3", "c4"])
        #expect(changes.suggestion.bump == .minor)
        #expect(changes.suggestion.tagName(for: .minor, beta: false) == "v0.2.0")
        #expect(changes.count(ofType: "feat") == 1)
        #expect(changes.count(ofType: "fix") == 1)

        let notes = changelog.notes(changes, slug: slug, tag: "v0.2.0")
        #expect(notes.hasPrefix("## Features\n\n- **github:** drop a version"))
        #expect(notes.contains("compare/v0.1.0...v0.2.0"))
    }

    @Test func usesTheRecentHistoryWhenThereIsNoTagYet() async throws {
        let repository = InMemoryRepositoryService(commits: [GitHubCommit(sha: "c1", message: "feat: first")])
        let changelog = ChangelogService(repository: repository, github: github)
        let changes = try await changelog.unreleased(slug, branch: "main")
        #expect(changes.since == nil)
        #expect(changes.commits.count == 1)
        #expect(changes.suggestion.tagName(for: changes.suggestion.bump, beta: false) == "v0.1.0")
    }

    @Test func opensAPullRequestInsteadOfPushingToTheBranch() async throws {
        let (changelog, repository) = service
        let pullRequest = try await changelog.openPullRequest(
            slug, base: "main", tag: "v0.2.0", notes: "### Features\n\n- drop a version"
        )
        #expect(pullRequest.number == 1)

        let state = repository.snapshot
        #expect(state.files["main"]?["CHANGELOG.md"]?.contains("v0.2.0") == false)
        let updated = try #require(state.files["changelog/v0.2.0"]?["CHANGELOG.md"])
        #expect(updated.hasPrefix("# Changelog\n\n## v0.2.0 - "))
        #expect(updated.contains("## v0.1.0 - 2026-10-01"))

        let change = try #require(state.fileChanges.first)
        #expect(change.message == "docs(changelog): add v0.2.0")
        let identity = GitHubIdentity(name: "kirikakaese", email: "252577764+kirikakaese@users.noreply.github.com")
        #expect(change.author == identity)
        #expect(change.committer == change.author)
        #expect(change.sha != nil)

        let opened = try #require(state.pullRequests.first)
        #expect(opened.title == "docs(changelog): add v0.2.0")
        #expect(opened.head == "changelog/v0.2.0")
        #expect(opened.base == "main")
    }

    @Test func aDropCanOpenTheChangelogPullRequestAsItsLastStep() async throws {
        let (changelog, repository) = service
        let releases = InMemoryReleaseService()
        let drops = DropService(
            releases: releases, metadata: InMemoryMetadataStore(), notifier: RecordingDropNotifier(),
            changelog: changelog
        )
        let request = DropRequest(
            projectID: UUID(), slug: slug, tagName: "v0.2.0", notes: "## Features\n\n- drop a version",
            target: .branch("main"), changelogBase: "main"
        )
        let plan = try await drops.plan(request)
        #expect(plan.steps.last == .openChangelogPullRequest(tag: "v0.2.0", base: "main"))
        // Planning opens nothing.
        #expect(repository.snapshot.pullRequests.isEmpty)

        let result = try await drops.execute(plan)
        #expect(result.changelogPullRequest?.number == 1)
        let updated = repository.snapshot.files["changelog/v0.2.0"]?["CHANGELOG.md"] ?? ""
        #expect(updated.contains("### Features"))
    }
}
