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
        try await propose(WorkflowProposal(
            path: WorkflowTemplate.path,
            text: WorkflowTemplate.release,
            branch: "ci/release-workflow",
            message: "ci: add a release workflow",
            body: """
                Adds a release workflow that builds every `v*` tag on Linux, macOS and Windows for \
                x86-64 and arm64 and uploads each build as an artifact.

                Replace the build step with the project's build before merging.

                """
        ), slug, base: base)
    }

    /// Opens a pull request against `base` that adds the workflow publishing to GHCR or npm, which
    /// DROP then starts on each tag. Refuses if the file exists already. Needs the `workflow` scope.
    public func proposePublishWorkflow(
        for destination: Destination,
        _ slug: RepositorySlug,
        base: String
    ) async throws -> GitHubPullRequest {
        guard let path = WorkflowTemplate.publishPath(for: destination),
            let text = WorkflowTemplate.publish(for: destination)
        else {
            throw DROPError(
                .invalidArgument,
                whatHappened: String(localized: "\(destination.title) isn't published by a workflow.")
            )
        }
        let proposal: WorkflowProposal
        if destination == .ghcr {
            proposal = WorkflowProposal(
                path: path, text: text, branch: "ci/publish-ghcr", message: "ci: publish images to ghcr",
                body: """
                    Adds a workflow that builds the Dockerfile for a tag and pushes the image to GitHub \
                    Container Registry with the workflow's own `GITHUB_TOKEN`. It starts by hand on a tag.

                    """
            )
        } else {
            proposal = WorkflowProposal(
                path: path, text: text, branch: "ci/publish-npm", message: "ci: publish the package to npm",
                body: """
                    Adds a workflow that publishes the package for a tag with provenance, through npm's \
                    trusted publishing, so no npm token is needed. It starts by hand on a tag.

                    Add this repository and workflow as a trusted publisher on npmjs.com before merging.

                    """
            )
        }
        return try await propose(proposal, slug, base: base)
    }

    private func propose(_ proposal: WorkflowProposal, _ slug: RepositorySlug, base: String) async throws
        -> GitHubPullRequest
    {
        if try await repository.file(slug, path: proposal.path, ref: base) != nil {
            throw DROPError(
                .alreadyExists,
                whatHappened: String(localized: "This repository already has \(proposal.path).")
            )
        }
        let identity = GitHubIdentity(user: try await github.currentUser())
        let head = try await repository.branchHead(slug, branch: base)
        try await repository.createBranch(slug, name: proposal.branch, from: head)
        try await repository.putFile(slug, path: proposal.path, change: FileChange(
            message: proposal.message, text: proposal.text, branch: proposal.branch, sha: nil, identity: identity
        ))
        return try await repository.openPullRequest(slug, NewPullRequest(
            title: proposal.message, head: proposal.branch, base: base, body: proposal.body
        ))
    }
}

/// A workflow file DROP offers to add through a pull request.
private struct WorkflowProposal {
    let path: String
    let text: String
    let branch: String
    let message: String
    let body: String
}
