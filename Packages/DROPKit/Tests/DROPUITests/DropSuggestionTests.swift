import DROPCore
import DROPGitHub
import DROPServices
import DROPTestFixtures
import Foundation
import Testing

@testable import DROPUI

@MainActor
@Suite("Drop suggestions")
struct DropSuggestionTests {
    let project = Project(slug: Fixtures.slug("octocat/Hello-World"), repositoryID: 42, addedAt: Fixtures.referenceDate)
    let repository = InMemoryRepositoryService(
        commits: [
            GitHubCommit(sha: "c1", message: "feat: first"),
            GitHubCommit(sha: "c2", message: "fix: second (#7)"),
            GitHubCommit(sha: "c3", message: "feat(ui): third (#8)"),
        ],
        tags: ["v1.0.0": "c1", "v1.1.0-beta.1": "c2"]
    )

    func makeDrop() async throws -> DropModel {
        let endpoint = ScriptedOAuthEndpoint()
        await endpoint.setPollResults([.success(.authorized(OAuthToken(accessToken: "t")))])
        let auth = AuthService(endpoint: endpoint, secrets: InMemorySecretStore(), sleep: { _ in })
        let services = ServiceContainer.preview(projects: [project], auth: auth, repository: repository)
        let account = AccountModel(services: services)
        account.signIn()
        await account.signInTask?.value
        let projects = ProjectsModel(services: services, account: account)
        projects.load()
        projects.selection = project.id
        projects.startDrop()
        let drop = try #require(projects.currentDrop)
        await drop.loadSuggestion()
        return drop
    }

    @Test func prefillsTheSuggestedTagAndNotes() async throws {
        let drop = try await makeDrop()
        #expect(drop.bump == .minor)
        #expect(drop.tagName == "v1.1.0")
        #expect(drop.notes.contains("- **ui:** third"))
        #expect(drop.notes.contains("compare/v1.0.0...v1.1.0"))
        #expect(drop.suggestionSummary?.hasPrefix("Since v1.0.0") == true)
    }

    @Test func followsTheBumpAndDropABeta() async throws {
        let drop = try await makeDrop()
        drop.isPrerelease = true
        #expect(drop.tagName == "v1.1.0-beta.2")
        drop.bump = .major
        #expect(drop.tagName == "v2.0.0-beta.1")
        #expect(drop.notes.contains("v1.0.0...v2.0.0-beta.1"))
    }

    @Test func keepsWhatYouTyped() async throws {
        let drop = try await makeDrop()
        drop.tagName = "v1.1.0-rc.1"
        drop.notes = "Hand-written notes"
        drop.bump = .patch
        #expect(drop.tagName == "v1.1.0-rc.1")
        #expect(drop.notes == "Hand-written notes")
    }

    @Test func asksForTheChangelogPullRequestOnlyWhenTurnedOn() async throws {
        let drop = try await makeDrop()
        #expect(drop.request.changelogBase == nil)
        drop.updatesChangelog = true
        #expect(drop.request.changelogBase == "main")
    }
}
