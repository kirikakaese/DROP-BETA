import DROPCore
import DROPGitHub
import DROPServices
import Foundation
import Observation

/// A project's GitHub Actions: workflows with their triggers, recent runs, running a workflow by
/// hand and proposing a release workflow.
@MainActor
@Observable
public final class ProjectActionsModel {
    public let project: Project
    public let defaultBranch: String
    public private(set) var workflows: [WorkflowSummary] = []
    public private(set) var runs: [GitHubWorkflowRun] = []
    public private(set) var branches: [GitHubBranch] = []
    public private(set) var isLoaded = false
    public var error: DROPError?
    /// The pull request that adds the release workflow, once opened.
    public private(set) var proposedWorkflow: GitHubPullRequest?
    /// Set when adding a workflow needs the `workflow` scope the account doesn't have yet.
    public private(set) var needsWorkflowScope = false

    // What the project view shows as sheets.
    public var openRun: GitHubWorkflowRun?
    public var dispatching: GitHubWorkflow?
    public var isProposingWorkflow = false

    /// How long to wait after starting a workflow before GitHub lists its run.
    var settleDelay: Duration = .seconds(3)

    private let services: ServiceContainer
    private let account: AccountModel
    private let attach: @MainActor ([URL]) -> Void

    init(
        project: Project,
        defaultBranch: String,
        services: ServiceContainer,
        account: AccountModel,
        attach: @escaping @MainActor ([URL]) -> Void
    ) {
        self.project = project
        self.defaultBranch = defaultBranch
        self.services = services
        self.account = account
        self.attach = attach
    }

    /// Whether a workflow starts when a tag is pushed, which is how most release workflows start.
    public var hasReleaseWorkflow: Bool {
        workflows.contains { $0.triggers.tagPush || $0.triggers.release }
    }

    public func workflowName(of run: GitHubWorkflowRun) -> String {
        workflows.first { $0.id == run.workflowID }?.workflow.name ?? run.name ?? ""
    }

    public func load() async {
        guard account.isSignedIn else { return }
        do {
            workflows = try await services.workflows.summaries(project.slug, ref: defaultBranch)
            runs = try await services.actions.runs(project.slug, workflowID: nil)
            isLoaded = true
        } catch {
            self.error = account.filter(error)
        }
    }

    public func loadBranches() async {
        guard branches.isEmpty else { return }
        branches = (try? await services.releases.branches(project.slug)) ?? []
    }

    /// Starts a workflow by hand and shows its run once GitHub lists it.
    public func dispatch(_ workflow: GitHubWorkflow, ref: String) async -> Bool {
        do {
            try await services.actions.dispatch(project.slug, workflowID: workflow.id, ref: ref)
            try? await Task.sleep(for: settleDelay)
            runs = try await services.actions.runs(project.slug, workflowID: nil)
            return true
        } catch {
            self.error = account.filter(error)
            return false
        }
    }

    /// Opens a pull request that adds the release workflow. Asks to sign in again first when the
    /// account doesn't have the `workflow` scope GitHub requires for workflow files.
    public func proposeReleaseWorkflow() async {
        guard await account.canChangeWorkflows() else {
            needsWorkflowScope = true
            return
        }
        needsWorkflowScope = false
        do {
            proposedWorkflow = try await services.workflows.proposeReleaseWorkflow(project.slug, base: defaultBranch)
        } catch {
            self.error = account.filter(error)
        }
    }

    /// Signs in again, this time also asking for the `workflow` scope.
    public func grantWorkflowScope() {
        account.signIn(scopes: OAuthConfiguration.workflowScopes)
    }

    public func runModel(for run: GitHubWorkflowRun) -> WorkflowRunModel {
        WorkflowRunModel(run: run, project: project, services: services, account: account, attach: attach)
    }
}

/// One run: its jobs and steps, the end of each job's log and its artifacts. Refreshes itself
/// while the run is going.
@MainActor
@Observable
public final class WorkflowRunModel {
    public private(set) var run: GitHubWorkflowRun
    public private(set) var jobs: [GitHubJob] = []
    public private(set) var artifacts: [GitHubArtifact] = []
    public private(set) var logs: [GitHubJob.ID: String] = [:]
    /// Artifacts being downloaded, and those already attached to the next drop.
    public private(set) var attaching: Set<GitHubArtifact.ID> = []
    public private(set) var attached: Set<GitHubArtifact.ID> = []
    public var error: DROPError?

    /// How often a running run is refreshed.
    static let refreshInterval: Duration = .seconds(5)

    private let project: Project
    private let services: ServiceContainer
    private let account: AccountModel
    private let attach: @MainActor ([URL]) -> Void

    init(
        run: GitHubWorkflowRun,
        project: Project,
        services: ServiceContainer,
        account: AccountModel,
        attach: @escaping @MainActor ([URL]) -> Void
    ) {
        self.run = run
        self.project = project
        self.services = services
        self.account = account
        self.attach = attach
    }

    public func refresh() async {
        do {
            run = try await services.actions.run(project.slug, id: run.id)
            jobs = try await services.actions.jobs(project.slug, runID: run.id)
            artifacts = try await services.actions.artifacts(project.slug, runID: run.id)
        } catch {
            self.error = account.filter(error)
        }
    }

    /// Refreshes until the run finishes or the task is cancelled (when the sheet closes).
    public func watch() async {
        await refresh()
        while !run.isFinished, !Task.isCancelled {
            try? await Task.sleep(for: Self.refreshInterval)
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    public func loadLog(of job: GitHubJob) async {
        do {
            logs[job.id] = try await services.actions.logTail(project.slug, jobID: job.id)
        } catch {
            self.error = account.filter(error)
        }
    }

    /// Downloads the artifact, unpacks it and adds its files to the next drop of the project.
    public func attachToNextDrop(_ artifact: GitHubArtifact) async {
        attaching.insert(artifact.id)
        defer { attaching.remove(artifact.id) }
        let directory = FileManager.default.temporaryDirectory
            .appending(path: "DROPArtifacts/\(run.id)/\(artifact.id)", directoryHint: .isDirectory)
        do {
            let files = try await services.actions.downloadArtifact(
                project.slug, artifactID: artifact.id, into: directory
            )
            attach(files)
            attached.insert(artifact.id)
        } catch {
            self.error = account.filter(error)
        }
    }
}
