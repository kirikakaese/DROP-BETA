import DROPCore
import DROPGitHub
import DROPServices
import DROPTestFixtures
import Foundation
import Testing

@testable import DROPUI

@MainActor
@Suite("ProjectsModel")
struct ProjectsModelTests {
    let github = InMemoryGitHubService(repositories: [
        GitHubRepository(id: 42, fullName: "octocat/Hello-World"),
        GitHubRepository(id: 43, fullName: "octocat/Spoon-Knife"),
    ])

    /// A signed-in model over in-memory services.
    func makeModel(projects: [Project] = []) async -> ProjectsModel {
        let endpoint = ScriptedOAuthEndpoint()
        await endpoint.setPollResults([.success(.authorized(OAuthToken(accessToken: "t")))])
        let auth = AuthService(endpoint: endpoint, secrets: InMemorySecretStore(), sleep: { _ in })
        let services = ServiceContainer.preview(projects: projects, auth: auth, github: github)
        let account = AccountModel(services: services)
        account.signIn()
        await account.signInTask?.value
        let model = ProjectsModel(services: services, account: account)
        model.load()
        return model
    }

    @Test func loadsProjectsAndDropsAStaleSelection() async throws {
        let smp = Fixtures.project("kirikakaese/SMP")
        let model = await makeModel(projects: [smp])
        model.selection = UUID()
        model.load()
        #expect(model.projects == [smp])
        #expect(model.selection == nil)

        model.selection = smp.id
        #expect(model.selectedProject == smp)
    }

    @Test func showsTheStartupIssue() {
        var services = ServiceContainer.preview()
        services.startupIssue = .storageUnavailable(details: "disk I/O error")
        let model = ProjectsModel(services: services, account: AccountModel(services: services))
        #expect(model.error?.code == .storage)
    }

    @Test func addsAProjectFromYourRepositoriesAndHidesItFromTheList() async throws {
        let model = await makeModel()
        await model.loadYourRepositories()
        #expect(model.yourRepositories.count == 2)

        #expect(await model.addProject("octocat/hello-world"))
        #expect(model.projects.map(\.slug.description) == ["octocat/Hello-World"])
        #expect(model.selection == model.projects.first?.id)
        #expect(model.isAdded(model.yourRepositories[0]))
        #expect(!model.isAdded(model.yourRepositories[1]))

        #expect(await model.addProject("octocat/Hello-World") == false)
        #expect(model.addError?.code == .alreadyExists)
    }

    @Test func refreshFollowsRenamesAndMarksMissingRepositories() async throws {
        let renamed = Project(
            slug: Fixtures.slug("octocat/Hello-World"),
            repositoryID: 42,
            addedAt: Fixtures.referenceDate
        )
        let gone = Project(
            slug: Fixtures.slug("octocat/gone"),
            repositoryID: 99,
            addedAt: Fixtures.referenceDate.addingTimeInterval(60)
        )
        let model = await makeModel(projects: [renamed, gone])
        github.rename(id: 42, to: "octocat/Hello-Universe")

        await model.refreshFromGitHub()
        #expect(model.projects.map(\.slug.description) == ["octocat/Hello-Universe", "octocat/gone"])
        #expect(model.repositories[renamed.id]?.id == 42)
        #expect(model.missing == [gone.id])
    }

    @Test func anEndedSessionDuringRefreshAsksToSignInAgain() async throws {
        let model = await makeModel(projects: [Fixtures.project("octocat/Hello-World")])
        github.setError(.sessionExpired)
        await model.refreshFromGitHub()
        #expect(model.account.phase == .sessionExpired)
        #expect(model.error == nil)
        #expect(!model.canAddProject)
    }

    @Test func removesAProjectOnlyFromDROP() async throws {
        let project = Fixtures.project("octocat/Hello-World")
        let model = await makeModel(projects: [project])
        model.selection = project.id
        model.removeProject(id: project.id)
        #expect(model.projects.isEmpty)
        #expect(model.selection == nil)
        #expect(try await github.repository(id: 42).id == 42)
    }
}

@Suite("DropWording")
struct DropWordingTests {
    @Test func namesTheVersionWhenItIsKnown() {
        #expect(DropWording.actionTitle(version: nil) == "Drop")
        #expect(DropWording.actionTitle(version: "") == "Drop")
        #expect(DropWording.actionTitle(version: "1.2.3") == "Drop v1.2.3")
        #expect(DropWording.actionTitle(version: "v1.2.3-beta.1") == "Drop v1.2.3-beta.1")
        #expect(DropWording.menuTitle == "Drop…")
    }
}
