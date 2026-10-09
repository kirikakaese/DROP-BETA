import DROPCore
import DROPGitHub
import DROPServices
import DROPTestFixtures
import Foundation
import Testing

@testable import DROPUI

@MainActor
@Suite("DropModel")
struct DropModelTests {
    let releases = InMemoryReleaseService()
    let project = Project(slug: Fixtures.slug("octocat/Hello-World"), repositoryID: 42, addedAt: Fixtures.referenceDate)

    func makeProjects() async -> ProjectsModel {
        let endpoint = ScriptedOAuthEndpoint()
        await endpoint.setPollResults([.success(.authorized(OAuthToken(accessToken: "t")))])
        let auth = AuthService(endpoint: endpoint, secrets: InMemorySecretStore(), sleep: { _ in })
        let github = InMemoryGitHubService(repositories: [GitHubRepository(id: 42, fullName: "octocat/Hello-World")])
        let services = ServiceContainer.preview(projects: [project], auth: auth, github: github, releases: releases)
        let account = AccountModel(services: services)
        account.signIn()
        await account.signInTask?.value
        let model = ProjectsModel(services: services, account: account)
        model.load()
        return model
    }

    @Test func dropIsAvailableOnlyForASelectedProjectWhileSignedIn() async {
        let projects = await makeProjects()
        #expect(!projects.canDrop)
        projects.selection = project.id
        #expect(projects.canDrop)
        projects.startDrop()
        #expect(projects.currentDrop?.project == project)
        #expect(!projects.canDrop)
    }

    @Test func reviewsThenDropsAndReportsEachStep() async throws {
        let projects = await makeProjects()
        projects.selection = project.id
        projects.startDrop()
        let drop = try #require(projects.currentDrop)
        #expect(drop.headline == "Drop")
        #expect(!drop.canReview)

        drop.tagName = "v1.0.0"
        drop.isPrerelease = true
        #expect(drop.headline == "Drop v1.0.0")
        await drop.review()
        guard case .ready(let plan) = drop.stage else {
            Issue.record("Expected the plan, got \(drop.stage)")
            return
        }
        #expect(drop.headline == "Ready to Drop")
        #expect(plan.steps == [.createTagAndRelease(tag: "v1.0.0", target: "main")])
        #expect(releases.snapshot.log.isEmpty)

        await drop.drop()
        guard case .dropped(_, let result) = drop.stage else {
            Issue.record("Expected the drop to finish, got \(drop.stage)")
            return
        }
        #expect(drop.headline == "Dropped v1.0.0")
        #expect(drop.stepStates == [.done])
        #expect(result.release.isPrerelease)
        #expect(projects.dropsFinished == 1)
    }

    @Test func aFailureShowsTheStepAndCanGoBackToTheForm() async throws {
        releases.update { $0.failingWrite = "create" }
        let projects = await makeProjects()
        projects.selection = project.id
        projects.startDrop()
        let drop = try #require(projects.currentDrop)
        drop.tagName = "v1.0.0"
        await drop.review()
        await drop.drop()
        guard case .failed(_, let error) = drop.stage else {
            Issue.record("Expected a failure, got \(drop.stage)")
            return
        }
        #expect(error.whatHappened.contains("v1.0.0"))
        #expect(drop.stepStates == [.failed])
        #expect(drop.headline == "Drop failed")
        drop.backToEditing()
        #expect(drop.stage == .editing)
    }

    @Test func aBadTagStaysInTheForm() async throws {
        let projects = await makeProjects()
        projects.selection = project.id
        projects.startDrop()
        let drop = try #require(projects.currentDrop)
        drop.tagName = "v1 .0"
        await drop.review()
        #expect(drop.stage == .editing)
        #expect(drop.formError?.code == .invalidArgument)
    }
}
