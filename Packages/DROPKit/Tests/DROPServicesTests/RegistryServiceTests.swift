import DROPCore
import DROPGitHub
import DROPPersistence
import DROPRegistries
import DROPTestFixtures
import Foundation
import Testing

@testable import DROPServices

private let oldSHA = String(repeating: "a", count: 64)
private let gitHubSHA = String(repeating: "b", count: 64)
private let localSHA = String(repeating: "c", count: 64)

/// A project, its Homebrew tap and the cask DROP keeps up to date. The in-memory repository keeps
/// every repository's files together.
struct TapFixture {
    static let cask = """
        cask "smp" do
          version "1.0.0"
          sha256 "\(oldSHA)"

          url "https://github.com/octocat/SMP/releases/download/v#{version}/SMP-#{version}.dmg"
          name "SMP"
          homepage "https://github.com/octocat/SMP"

          app "SMP.app"
        end

        """

    let project = Fixtures.project("octocat/SMP")
    let setup = RegistrySetup(
        destination: .homebrewTap,
        repository: "octocat/homebrew-tap",
        path: "Casks/smp.rb",
        assetPattern: "SMP-{version}.dmg"
    )
    let repository: InMemoryRepositoryService
    let github = InMemoryGitHubService(
        user: GitHubUser(id: 7, login: "octocat"),
        repositories: [
            GitHubRepository(id: 1, fullName: "octocat/SMP", summary: "SSH keys and hosts."),
            GitHubRepository(id: 2, fullName: "octocat/homebrew-tap"),
        ]
    )
    let actions = InMemoryActionsService()
    let metadata = InMemoryMetadataStore()

    init(workflows: [String: String] = [".github/workflows/ci.yml": "on: push\n"]) {
        repository = InMemoryRepositoryService(files: workflows.merging(["Casks/smp.rb": Self.cask]) { $1 })
        let listed = workflows.keys.sorted().enumerated().map { index, path in
            GitHubWorkflow(id: Int64(index + 1), name: path, path: path)
        }
        actions.update { $0.workflows = listed }
    }

    var service: RegistryService {
        RegistryService(repository: repository, github: github, actions: actions, metadata: metadata)
    }

    /// The dry run for the release.
    func edit() async throws -> RegistryEdit {
        try await service.edit(setup, project: project.slug, release: release())
    }

    func release(digest: String? = "sha256:\(gitHubSHA)") -> GitHubRelease {
        GitHubRelease(id: 5, tagName: "v1.1.0", assets: [
            GitHubAsset(id: 1, name: "SMP-1.1.0.dmg", size: 10, digest: digest),
            GitHubAsset(id: 2, name: "SMP-1.1.0.zip", size: 10, digest: "sha256:\(oldSHA)"),
            GitHubAsset(id: 3, name: Checksums.fileName, size: 10, digest: "sha256:\(oldSHA)"),
        ])
    }
}

@Suite("Registries")
struct RegistryServiceTests {
    @Test func checkAcceptsAFileNobodyElseWrites() async throws {
        let fixture = TapFixture()
        try await fixture.service.check(fixture.setup, project: fixture.project.slug, ref: "main")
    }

    @Test func checkRefusesAFileAnotherWorkflowWrites() async throws {
        let fixture = TapFixture(workflows: [
            ".github/workflows/release.yml": "run: git -C tap add Casks/smp.rb && git -C tap push",
        ])
        await #expect(throws: DROPError.self) {
            try await fixture.service.check(fixture.setup, project: fixture.project.slug, ref: "main")
        }
    }

    @Test func checkRefusesATapItCantRead() async throws {
        let fixture = TapFixture()
        var setup = fixture.setup
        setup.repository = "octocat/missing"
        await #expect(throws: DROPError.self) {
            try await fixture.service.check(setup, project: fixture.project.slug, ref: "main")
        }
    }

    @Test func dryRunUsesGitHubsChecksumUnlessDROPUploadedTheFile() async throws {
        let fixture = TapFixture()
        let edit = try await fixture.edit()
        #expect(edit.assetName == "SMP-1.1.0.dmg")
        #expect(edit.sha256 == gitHubSHA)
        #expect(edit.newText.contains("version \"1.1.0\""))
        #expect(fixture.repository.snapshot.fileChanges.isEmpty)

        let local = try await fixture.service.edit(
            fixture.setup, project: fixture.project.slug, release: fixture.release(),
            localChecksums: ["SMP-1.1.0.dmg": localSHA]
        )
        #expect(local.sha256 == localSHA)
    }

    @Test func dryRunNeedsAChecksum() async throws {
        let fixture = TapFixture()
        await #expect(throws: DROPError.self) {
            try await fixture.service.edit(
                fixture.setup, project: fixture.project.slug, release: fixture.release(digest: nil)
            )
        }
    }

    @Test func publishOpensAPullRequestAsTheAccount() async throws {
        let fixture = TapFixture()
        let edit = try await fixture.edit()
        let pullRequest = try await fixture.service.publish(edit, mode: .pullRequest)
        try await fixture.service.verify(edit, mode: .pullRequest)

        let state = fixture.repository.snapshot
        #expect(pullRequest?.number == 1)
        #expect(state.pullRequests.first?.title == "smp 1.1.0")
        #expect(state.pullRequests.first?.head == "drop/smp-1.1.0")
        #expect(state.pullRequests.first?.base == "main")
        #expect(state.fileChanges.first?.message == "smp 1.1.0")
        #expect(state.fileChanges.first?.author.email == "7+octocat@users.noreply.github.com")
        #expect(state.files["main"]?["Casks/smp.rb"] == TapFixture.cask)
        #expect(state.files["drop/smp-1.1.0"]?["Casks/smp.rb"]?.contains(gitHubSHA) == true)
    }

    @Test func directCommitWritesTheDefaultBranch() async throws {
        let fixture = TapFixture()
        let edit = try await fixture.edit()
        await #expect(throws: DROPError.self) { try await fixture.service.verify(edit, mode: .directCommit) }

        let pullRequest = try await fixture.service.publish(edit, mode: .directCommit)
        try await fixture.service.verify(edit, mode: .directCommit)
        #expect(pullRequest == nil)
        #expect(fixture.repository.snapshot.pullRequests.isEmpty)
        #expect(fixture.repository.snapshot.files["main"]?["Casks/smp.rb"]?.contains("1.1.0") == true)
    }

    @Test func publishWorkflowProposalAddsTheTemplate() async throws {
        let fixture = TapFixture()
        let workflows = WorkflowService(
            actions: fixture.actions, repository: fixture.repository, github: fixture.github
        )
        let pullRequest = try await workflows.proposePublishWorkflow(for: .npm, fixture.project.slug, base: "main")
        let state = fixture.repository.snapshot
        #expect(pullRequest.number == 1)
        #expect(state.pullRequests.first?.title == "ci: publish the package to npm")
        #expect(state.files["ci/publish-npm"]?[".github/workflows/publish-npm.yml"] == WorkflowTemplate.npm)
        await #expect(throws: DROPError.self) {
            try await workflows.proposePublishWorkflow(for: .homebrewTap, fixture.project.slug, base: "main")
        }
    }
}

@Suite("Drops that publish to registries")
struct RegistryDropTests {
    let fixture = TapFixture()
    let releases = InMemoryReleaseService()
    let npm = RegistrySetup(destination: .npm, workflowID: 40, workflowName: "publish-npm.yml")

    var service: DropService {
        DropService(
            releases: releases, metadata: fixture.metadata, notifier: RecordingDropNotifier(),
            repository: fixture.repository, actions: fixture.actions, registries: fixture.service,
            sleep: { _ in }, pollInterval: .zero, workflowTimeout: 60
        )
    }

    func request(
        assets: [DropAsset] = [],
        registries: [RegistrySetup],
        isPrerelease: Bool = false,
        isDraft: Bool = false
    ) -> DropRequest {
        DropRequest(
            projectID: fixture.project.id,
            slug: fixture.project.slug,
            tagName: "v1.1.0",
            target: .branch("main"),
            isDraft: isDraft,
            isPrerelease: isPrerelease,
            assets: assets,
            registries: registries
        )
    }

    func dmg() throws -> DropAsset {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: "SMP-1.1.0.dmg")
        try Data("disk image".utf8).write(to: url)
        return DropAsset(fileURL: url, size: 10)
    }

    @Test func tapIsUpdatedAfterTheGitHubRelease() async throws {
        let asset = try dmg()
        let plan = try await service.plan(request(assets: [asset], registries: [fixture.setup]))
        let lastSteps = Array(plan.steps.suffix(2))
        #expect(lastSteps == [
            .updateRegistryFile(
                destination: .homebrewTap, repository: "octocat/homebrew-tap", path: "Casks/smp.rb",
                viaPullRequest: true
            ),
            .verifyRegistryFile(destination: .homebrewTap, repository: "octocat/homebrew-tap", path: "Casks/smp.rb"),
        ])

        let result = try await service.execute(plan)
        #expect(result.registryPullRequests.count == 1)
        let expected = try Checksums.sha256(of: asset.fileURL)
        let cask = fixture.repository.snapshot.files["drop/smp-1.1.0"]?["Casks/smp.rb"]
        #expect(cask?.contains(expected) == true)
    }

    @Test func planRefusesAPatternNoAssetMatches() async throws {
        var setup = fixture.setup
        setup.assetPattern = "*.pkg"
        let asset = try dmg()
        await #expect(throws: DROPError.self) {
            try await service.plan(request(assets: [asset], registries: [setup]))
        }
    }

    @Test func betasSkipTapsAndDraftsSkipEverything() async throws {
        let beta = try await service.plan(request(registries: [fixture.setup, npm], isPrerelease: true))
        let betaRegistries = beta.steps.compactMap(\.registry)
        #expect(betaRegistries == [.npm, .npm])

        let draft = try await service.plan(request(registries: [fixture.setup, npm], isDraft: true))
        let draftRegistries = draft.steps.compactMap(\.registry)
        #expect(draftRegistries.isEmpty)
    }

    @Test func publishWorkflowRunsOnTheTag() async throws {
        fixture.actions.update { state in
            state.runs.append(GitHubWorkflowRun(
                id: 90, workflowID: 40, headBranch: "v1.1.0", status: "completed", conclusion: "success"
            ))
        }
        let plan = try await service.plan(request(registries: [npm]))
        let lastSteps = Array(plan.steps.suffix(2))
        #expect(lastSteps == [
            .dispatchPublishWorkflow(destination: .npm, name: "publish-npm.yml", workflowID: 40, tag: "v1.1.0"),
            .awaitPublishWorkflow(destination: .npm, name: "publish-npm.yml", workflowID: 40, tag: "v1.1.0"),
        ])
        #expect(lastSteps.last?.performer == .automation("publish-npm.yml"))
        _ = try await service.execute(plan)
        #expect(fixture.actions.snapshot.dispatches == ["40@v1.1.0"])
    }
}
