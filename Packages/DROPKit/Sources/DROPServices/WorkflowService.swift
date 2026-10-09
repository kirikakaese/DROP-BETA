import DROPCore
import DROPGitHub
import Foundation

/// A workflow together with how it starts.
public struct WorkflowSummary: Sendable, Equatable, Identifiable {
    public let workflow: GitHubWorkflow
    public let triggers: WorkflowTriggers
    /// The workflow file as it is on the branch it was read from.
    public let source: String

    public init(workflow: GitHubWorkflow, triggers: WorkflowTriggers, source: String = "") {
        self.workflow = workflow
        self.triggers = triggers
        self.source = source
    }

    public var id: Int64 { workflow.id }
}

/// Reads a repository's workflows with their triggers, and adds a release workflow through a pull
/// request for repositories that have none.
public struct WorkflowService: Sendable {
    let actions: any ActionsServicing
    let repository: any RepositoryServicing
    let github: any GitHubServicing

    public init(actions: any ActionsServicing, repository: any RepositoryServicing, github: any GitHubServicing) {
        self.actions = actions
        self.repository = repository
        self.github = github
    }

    /// The active workflows, with triggers read from the files on `ref`.
    public func summaries(_ slug: RepositorySlug, ref: String) async throws -> [WorkflowSummary] {
        var summaries: [WorkflowSummary] = []
        for workflow in try await actions.workflows(slug) where workflow.isActive {
            let file = try? await repository.file(slug, path: workflow.path, ref: ref)
            let source = file?.text ?? ""
            let triggers = WorkflowTriggers(yaml: source)
            summaries.append(WorkflowSummary(workflow: workflow, triggers: triggers, source: source))
        }
        return summaries
    }

    /// Opens a pull request against `base` that adds `WorkflowTemplate.release`. Refuses if the file
    /// exists already. Needs the `workflow` scope.
    public func proposeReleaseWorkflow(_ slug: RepositorySlug, base: String) async throws -> GitHubPullRequest {
        if try await repository.file(slug, path: WorkflowTemplate.path, ref: base) != nil {
            throw DROPError(
                .alreadyExists,
                whatHappened: String(localized: "This repository already has \(WorkflowTemplate.path).")
            )
        }
        let identity = GitHubIdentity(user: try await github.currentUser())
        let branch = "ci/release-workflow"
        let head = try await repository.branchHead(slug, branch: base)
        try await repository.createBranch(slug, name: branch, from: head)
        let message = "ci: add a release workflow"
        try await repository.putFile(slug, path: WorkflowTemplate.path, change: FileChange(
            message: message, text: WorkflowTemplate.release, branch: branch, sha: nil, identity: identity
        ))
        return try await repository.openPullRequest(slug, NewPullRequest(
            title: message,
            head: branch,
            base: base,
            body: """
                Adds a release workflow that builds every `v*` tag on Linux, macOS and Windows for \
                x86-64 and arm64 and uploads each build as an artifact.

                Replace the build step with the project's build before merging.

                """
        ))
    }
}
