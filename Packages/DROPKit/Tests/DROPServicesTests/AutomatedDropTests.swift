import DROPCore
import DROPGitHub
import DROPPersistence
import DROPTestFixtures
import Foundation
import Testing

@testable import DROPServices

@Suite("Drops with existing automation")
struct AutomatedDropTests {
    let project = Fixtures.project("octocat/Hello-World")
    let releases = InMemoryReleaseService(tags: ["v1.0.0"])
    let repository = InMemoryRepositoryService(
        commits: [
            GitHubCommit(sha: "c1aaaaa", message: "feat: first"),
            GitHubCommit(sha: "c2bbbbb", message: "fix: x"),
        ],
        tags: ["v1.0.0": "c1aaaaa"]
    )
    let actions = InMemoryActionsService()
    let metadata = InMemoryMetadataStore()

    static let releaseWorkflow = """
        on:
          push:
            tags: ['v*']
        jobs:
          r:
            steps:
              - run: gh release create v
        """

    var service: DropService {
        DropService(
            releases: releases, metadata: metadata, notifier: RecordingDropNotifier(),
            repository: repository, actions: actions, sleep: { _ in }, pollInterval: .zero, workflowTimeout: 60
        )
    }

    func request(startsOnTag: Bool = true, tag: String = "v1.1.0") -> DropRequest {
        DropRequest(
            projectID: project.id,
            slug: project.slug,
            tagName: tag,
            target: .branch("main"),
            releaseAutomation: ReleaseAutomation(workflowID: 9, name: "release.yml", startsOnTag: startsOnTag),
            externalDestinations: [
                DestinationSetting(destination: .homebrewTap, mode: .external, owner: ".github/workflows/release.yml"),
            ]
        )
    }

    /// What release.yml would do once the tag is there: a successful run and the GitHub Release.
    func workflowFinishes(_ conclusion: String = "success", tag: String = "v1.1.0") {
        actions.update { state in
            state.runs.append(GitHubWorkflowRun(
                id: 77, workflowID: 9, headBranch: tag, status: "completed", conclusion: conclusion
            ))
        }
        if conclusion == "success" {
            releases.update { state in
                state.releases.append(GitHubRelease(id: 5, tagName: tag, htmlURL: URL(string: "https://example.com/r")))
            }
        }
    }

    @Test func onlyPushesTheTagWhenTheWorkflowStartsOnTags() async throws {
        let plan = try await service.plan(request())
        #expect(plan.steps == [
            .pushTag(tag: "v1.1.0", target: "main"),
            .awaitWorkflow(name: "release.yml", workflowID: 9, tag: "v1.1.0"),
            .verifyGitHubRelease(tag: "v1.1.0", createdBy: "release.yml"),
            .leaveToAutomation(destination: .homebrewTap, owner: ".github/workflows/release.yml"),
        ])
        #expect(plan.steps.map(\.performer.title) == ["DROP", "release.yml", "DROP", "release.yml"])
    }

    @Test func startsTheWorkflowWhenItRunsOnlyByHand() async throws {
        let plan = try await service.plan(request(startsOnTag: false))
        #expect(plan.steps.prefix(3) == [
            .pushTag(tag: "v1.1.0", target: "main"),
            .dispatchWorkflow(name: "release.yml", workflowID: 9, tag: "v1.1.0"),
            .awaitWorkflow(name: "release.yml", workflowID: 9, tag: "v1.1.0"),
        ])
    }

    @Test func refusesATagThatExistsWhenOnlyAPushStartsTheWorkflow() async {
        await #expect(throws: DROPError.self) { try await service.plan(request(tag: "v1.0.0")) }
        // Started by hand, an existing tag is fine: the workflow runs on it.
        let plan = try? await service.plan(request(startsOnTag: false, tag: "v1.0.0"))
        #expect(plan?.steps.first == .dispatchWorkflow(name: "release.yml", workflowID: 9, tag: "v1.0.0"))
    }

    @Test func pushesTheTagWaitsAndVerifiesWithoutCreatingTheRelease() async throws {
        let plan = try await service.plan(request(startsOnTag: false))
        workflowFinishes()
        let result = try await service.execute(plan)

        #expect(repository.snapshot.tags["v1.1.0"] == "c2bbbbb")
        #expect(actions.snapshot.dispatches == ["9@v1.1.0"])
        // DROP never created the GitHub Release itself.
        let created = releases.snapshot.log.filter { $0.hasPrefix("create") }
        #expect(created.isEmpty)
        #expect(result.release.id == 5)
        #expect(result.workflowRun?.id == 77)
    }

    @Test func aFailedWorkflowFailsTheDrop() async throws {
        let plan = try await service.plan(request())
        workflowFinishes("failure")
        do {
            _ = try await service.execute(plan)
            Issue.record("Expected the drop to fail")
        } catch let error as DROPError {
            #expect(error.whatHappened.contains("release.yml"))
        }
    }

    @Test func aWorkflowThatNeverFinishesTimesOut() async throws {
        let clock = TestClock()
        let service = DropService(
            releases: releases, metadata: metadata, notifier: RecordingDropNotifier(),
            repository: repository, actions: actions, now: { clock.now },
            sleep: { _ in clock.advance(by: 30) }, pollInterval: .zero, workflowTimeout: 60
        )
        let plan = try await service.plan(request())
        await #expect(throws: DROPError.self) { try await service.execute(plan) }
    }

    @Test func detectsTheAutomationOfARepository() async throws {
        let actions = InMemoryActionsService()
        actions.update { state in
            state.workflows = [GitHubWorkflow(id: 9, name: "Release", path: ".github/workflows/release.yml")]
        }
        let repository = InMemoryRepositoryService(files: [".github/workflows/release.yml": Self.releaseWorkflow])
        let workflows = WorkflowService(actions: actions, repository: repository, github: InMemoryGitHubService())
        let automation = AutomationService(workflows: workflows, repository: repository, metadata: metadata)
        let report = try await automation.report(for: project, ref: "main")
        #expect(report.setting(for: .githubRelease).mode == .external)
        #expect(report.releaseAutomation == ReleaseAutomation(workflowID: 9, name: "release.yml", startsOnTag: true))

        try metadata.saveProject(project)
        try automation.save(DestinationSetting(destination: .githubRelease, mode: .managed), for: project)
        let changed = try await automation.report(for: project, ref: "main")
        #expect(changed.releaseAutomation == nil)
    }
}
