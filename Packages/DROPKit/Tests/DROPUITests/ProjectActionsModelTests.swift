import DROPCore
import DROPGitHub
import DROPServices
import DROPTestFixtures
import Foundation
import Testing

@testable import DROPUI

@MainActor
@Suite("ProjectActionsModel")
struct ProjectActionsModelTests {
    let project = Project(slug: Fixtures.slug("octocat/Hello-World"), repositoryID: 42, addedAt: Fixtures.referenceDate)
    let actions: InMemoryActionsService = {
        var state = InMemoryActionsService.State()
        state.workflows = [GitHubWorkflow(id: 2, name: "Release", path: ".github/workflows/release.yml")]
        state.runs = [
            GitHubWorkflowRun(id: 7, workflowID: 2, name: "Release", status: "completed", conclusion: "success"),
        ]
        state.artifacts[7] = [GitHubArtifact(id: 70, name: "build-linux", size: 3)]
        state.artifactFiles[70] = ["app-linux.tar.gz": "tar"]
        return InMemoryActionsService(state)
    }()

    func makeProjects(scopes: [String] = ["repo"]) async -> ProjectsModel {
        let endpoint = ScriptedOAuthEndpoint()
        await endpoint.setPollResults([.success(.authorized(OAuthToken(accessToken: "t", scopes: scopes)))])
        let auth = AuthService(endpoint: endpoint, secrets: InMemorySecretStore(), sleep: { _ in })
        let repository = InMemoryRepositoryService(files: [
            ".github/workflows/release.yml": "on:\n  push:\n    tags: [v*]\n",
        ])
        let services = ServiceContainer.preview(
            projects: [project], auth: auth, repository: repository, actions: actions
        )
        let account = AccountModel(services: services)
        account.signIn()
        await account.signInTask?.value
        let projects = ProjectsModel(services: services, account: account)
        projects.load()
        return projects
    }

    @Test func loadsWorkflowsAndRuns() async {
        let projects = await makeProjects()
        let model = projects.actionsModel(for: project)
        await model.load()
        #expect(model.isLoaded)
        #expect(model.hasReleaseWorkflow)
        #expect(model.workflowName(of: model.runs[0]) == "Release")
    }

    @Test func dispatchesAWorkflow() async {
        let projects = await makeProjects()
        let model = projects.actionsModel(for: project)
        model.settleDelay = .zero
        await model.load()
        #expect(await model.dispatch(model.workflows[0].workflow, ref: "main"))
        #expect(actions.snapshot.dispatches == ["2@main"])
    }

    @Test func attachedArtifactsGoIntoTheNextDrop() async throws {
        let projects = await makeProjects()
        let model = projects.actionsModel(for: project)
        await model.load()
        let run = model.runModel(for: model.runs[0])
        await run.refresh()
        await run.attachToNextDrop(run.artifacts[0])
        #expect(run.attached == [70])

        projects.selection = project.id
        projects.startDrop()
        let drop = try #require(projects.currentDrop)
        #expect(drop.assets.map(\.name) == ["app-linux.tar.gz"])
        #expect(projects.pendingAssets.isEmpty)
    }

    @Test func asksForTheWorkflowScopeBeforeAddingAWorkflow() async {
        let projects = await makeProjects(scopes: ["repo"])
        let model = projects.actionsModel(for: project)
        await model.proposeReleaseWorkflow()
        #expect(model.needsWorkflowScope)
        #expect(model.proposedWorkflow == nil)
    }
}
