import DROPCore
import DROPGitHub
import DROPTestFixtures
import Foundation
import Testing

@testable import DROPServices

@Suite("Actions and workflows")
struct ActionsServiceTests {
    let slug = Fixtures.slug("octocat/Hello-World")
    let github = InMemoryGitHubService(user: GitHubUser(id: 252_577_764, login: "kirikakaese"))

    func makeActions() -> InMemoryActionsService {
        var state = InMemoryActionsService.State()
        state.workflows = [
            GitHubWorkflow(id: 1, name: "CI", path: ".github/workflows/ci.yml"),
            GitHubWorkflow(id: 2, name: "Release", path: ".github/workflows/release.yml"),
            GitHubWorkflow(id: 3, name: "Old", path: ".github/workflows/old.yml", state: "disabled_manually"),
        ]
        return InMemoryActionsService(state)
    }

    @Test func readsTheTriggersOfActiveWorkflows() async throws {
        let repository = InMemoryRepositoryService(files: [
            ".github/workflows/ci.yml": "on:\n  pull_request:\n  workflow_dispatch:\n",
            ".github/workflows/release.yml": "on:\n  push:\n    tags: ['v*']\n",
        ])
        let service = WorkflowService(actions: makeActions(), repository: repository, github: github)
        let summaries = try await service.summaries(slug, ref: "main")
        #expect(summaries.map(\.workflow.name) == ["CI", "Release"])
        #expect(summaries[0].triggers.dispatch)
        #expect(summaries[1].triggers.startsOnPush(of: "v1.0.0"))
    }

    @Test func proposesTheReleaseWorkflowThroughAPullRequest() async throws {
        let repository = InMemoryRepositoryService(commits: [GitHubCommit(sha: "c1", message: "feat: x")])
        let service = WorkflowService(actions: makeActions(), repository: repository, github: github)
        let pullRequest = try await service.proposeReleaseWorkflow(slug, base: "main")
        #expect(pullRequest.number == 1)

        let state = repository.snapshot
        #expect(state.files["main"]?[WorkflowTemplate.path] == nil)
        #expect(state.files["ci/release-workflow"]?[WorkflowTemplate.path] == WorkflowTemplate.release)
        #expect(state.fileChanges.first?.message == "ci: add a release workflow")
        #expect(state.fileChanges.first?.author.email == "252577764+kirikakaese@users.noreply.github.com")
        #expect(state.pullRequests.first?.base == "main")

        // The template itself starts on v* tags and by hand, and builds six targets.
        let triggers = WorkflowTriggers(yaml: WorkflowTemplate.release)
        #expect(triggers.startsOnPush(of: "v1.0.0"))
        #expect(triggers.dispatch)
        #expect(WorkflowTemplate.release.components(separatedBy: "runner: ").count == 7)
    }

    @Test func refusesToReplaceAnExistingReleaseWorkflow() async throws {
        let repository = InMemoryRepositoryService(files: [WorkflowTemplate.path: "on: push\n"])
        let service = WorkflowService(actions: makeActions(), repository: repository, github: github)
        await #expect(throws: DROPError.self) { try await service.proposeReleaseWorkflow(slug, base: "main") }
        #expect(repository.snapshot.pullRequests.isEmpty)
    }

    @Test func unpacksArtifactsAndDropsLinks() throws {
        let root = FileManager.default.temporaryDirectory.appending(path: "ArtifactTests-\(UUID().uuidString)")
        let source = root.appending(path: "source")
        let target = root.appending(path: "target")
        try FileManager.default.createDirectory(at: source.appending(path: "nested"), withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        try Data("app".utf8).write(to: source.appending(path: "app.zip"))
        try Data("notes".utf8).write(to: source.appending(path: "nested/notes.txt"))
        try FileManager.default.createSymbolicLink(
            at: source.appending(path: "escape"), withDestinationURL: URL(filePath: "/etc/hosts")
        )

        let zip = root.appending(path: "artifact.zip")
        let ditto = Process()
        ditto.executableURL = URL(filePath: "/usr/bin/ditto")
        ditto.arguments = ["-c", "-k", source.path, zip.path]
        try ditto.run()
        ditto.waitUntilExit()

        let files = try ArtifactArchive.extract(zip, into: target)
        #expect(files.map(\.lastPathComponent) == ["app.zip", "notes.txt"])
        #expect(!FileManager.default.fileExists(atPath: target.appending(path: "escape").path))
    }

    @Test func logTailsSurviveACutUTF8Character() {
        let text = "é log"
        let cut = Data(text.utf8).dropFirst()
        #expect(LiveActionsService.text(from: Data(cut)) == " log")
    }
}
