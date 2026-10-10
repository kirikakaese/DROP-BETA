import DROPCore
import DROPGitHub
import DROPServices
import DROPTestFixtures
import Foundation
import Testing

@testable import DROPUI

@MainActor
@Suite("Destinations")
struct DestinationsTests {
    let project = Project(slug: Fixtures.slug("octocat/Hello-World"), repositoryID: 42, addedAt: Fixtures.referenceDate)

    func makeActivity() async -> ProjectActivityModel {
        let endpoint = ScriptedOAuthEndpoint()
        await endpoint.setPollResults([.success(.authorized(OAuthToken(accessToken: "t")))])
        let auth = AuthService(endpoint: endpoint, secrets: InMemorySecretStore(), sleep: { _ in })
        let actions = InMemoryActionsService()
        actions.update { state in
            state.workflows = [GitHubWorkflow(id: 9, name: "Release", path: ".github/workflows/release.yml")]
        }
        let workflow = "on:\n  push:\n    tags: ['v*']\njobs:\n  r:\n    steps:\n      - run: gh release create v\n"
        let repository = InMemoryRepositoryService(files: [".github/workflows/release.yml": workflow])
        let services = ServiceContainer.preview(
            projects: [project], auth: auth, repository: repository, actions: actions
        )
        let account = AccountModel(services: services)
        account.signIn()
        await account.signInTask?.value
        let activity = ProjectActivityModel(project: project, services: services, account: account)
        await activity.load(branch: "main")
        return activity
    }

    @Test func takingOverFromAnAutomationNeedsAConfirmation() async throws {
        let activity = await makeActivity()
        #expect(activity.automation?.setting(for: .githubRelease).mode == .external)

        activity.setMode(.managed, for: .githubRelease)
        #expect(activity.pendingTakeover?.destination == .githubRelease)
        #expect(activity.automation?.setting(for: .githubRelease).mode == .external)

        activity.confirmTakeover()
        #expect(activity.pendingTakeover == nil)
        #expect(activity.automation?.setting(for: .githubRelease).mode == .managed)
        #expect(activity.automation?.releaseAutomation == nil)
    }

    @Test func otherChangesApplyAtOnce() async throws {
        let activity = await makeActivity()
        activity.setMode(.off, for: .githubRelease)
        #expect(activity.pendingTakeover == nil)
        #expect(activity.automation?.setting(for: .githubRelease).mode == .off)
    }

    @Test func registriesCanBeManagedOnceSetUp() async throws {
        let activity = await makeActivity()
        activity.setMode(.managed, for: .scoopBucket)
        #expect(activity.pendingTakeover == nil)
        #expect(activity.automation?.setting(for: .scoopBucket).mode == .managed)

        activity.editSetup(for: .scoopBucket)
        var setup = try #require(activity.editingRegistry)
        #expect(setup.repository == "octocat/scoop-bucket")
        #expect(setup.path == "bucket/hello-world.json")
        setup.assetPattern = "hello-{version}-windows.zip"
        activity.saveSetup(setup)

        #expect(activity.editingRegistry == nil)
        #expect(activity.registrySetups[.scoopBucket] == setup)
        #expect(activity.setup(for: .scoopBucket).isComplete)
    }
}
