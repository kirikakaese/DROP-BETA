import DROPCore
import DROPGitHub
import DROPPersistence
import DROPRegistries
import Foundation

/// Publishes to the registries DROP manages. For Homebrew and Scoop it updates one file in the tap
/// or bucket repository, through a pull request unless you chose direct commits, and never a file
/// that another automation writes. GHCR and npm are published by a workflow DROP starts (see
/// `DropService`), so DROP holds no registry token.
///
/// Every write has a dry run: `edit` computes the change without writing anything.
public struct RegistryService: Sendable {
    let repository: any RepositoryServicing
    let github: any GitHubServicing
    let actions: any ActionsServicing
    let metadata: any MetadataStoring

    public init(
        repository: any RepositoryServicing,
        github: any GitHubServicing,
        actions: any ActionsServicing,
        metadata: any MetadataStoring
    ) {
        self.repository = repository
        self.github = github
        self.actions = actions
        self.metadata = metadata
    }

    // MARK: Setup

    /// The setups saved for the project.
    public func setups(for project: Project) -> [RegistrySetup] {
        (try? metadata.registrySetups(projectID: project.id)) ?? []
    }

    public func save(_ setup: RegistrySetup, for project: Project) throws {
        try metadata.saveRegistrySetup(setup, projectID: project.id)
    }

    // MARK: Checking (reads only)

    /// Checks that DROP may update the setup's file: the tap or bucket can be read, no workflow of the
    /// project or of the tap writes the file, and the file is in a format DROP can update. Reads only.
    public func check(_ setup: RegistrySetup, project: RepositorySlug, ref: String) async throws {
        guard setup.writesFile else { return }
        guard let tap = setup.repositorySlug else { throw DROPError.registryNotSetUp(setup.destination) }
        let branch = try await github.repository(tap).defaultBranch
        var files = try await workflowFiles(project, ref: ref)
        for (path, text) in try await workflowFiles(tap, ref: branch) {
            files["\(tap)/\(path)"] = text
        }
        if let owner = TapOwnership.owner(of: setup.path, in: files) {
            throw DROPError.registryFileOwned(setup.path, by: owner)
        }
        let existing = try await repository.file(tap, path: setup.path, ref: branch)
        // A dry run with placeholder values finds files DROP can't update before anything is written.
        _ = try RegistryEditor.edit(
            setup,
            project: project,
            tag: "v0.0.0",
            asset: SelectedAsset(name: "placeholder", sha256: String(repeating: "0", count: 64)),
            existing: existing
        )
    }

    /// The workflow files of a repository on `ref`, path → text.
    private func workflowFiles(_ slug: RepositorySlug, ref: String) async throws -> [String: String] {
        var files: [String: String] = [:]
        for workflow in try await actions.workflows(slug) {
            if let file = try? await repository.file(slug, path: workflow.path, ref: ref) {
                files[workflow.path] = file.text
            }
        }
        return files
    }

    // MARK: Dry run

    /// The change the setup makes for `release`, without writing anything. The checksum comes from
    /// `localChecksums` (files DROP uploaded) or else from GitHub's digest of the asset.
    public func edit(
        _ setup: RegistrySetup,
        project: RepositorySlug,
        release: GitHubRelease,
        localChecksums: [String: String] = [:]
    ) async throws -> RegistryEdit {
        guard let tap = setup.repositorySlug else { throw DROPError.registryNotSetUp(setup.destination) }
        let version = AssetPattern.version(fromTag: release.tagName)
        let names = release.assets.map(\.name).filter { $0 != Checksums.fileName }
        let name = try AssetPattern.select(from: names, pattern: setup.assetPattern, version: version)
        let reported = release.assets.first { $0.name == name }?.sha256
        guard let sha256 = localChecksums[name] ?? reported else {
            throw DROPError(
                .notFound,
                whatHappened: String(localized: "GitHub reported no checksum for “\(name)”."),
                howToFix: String(localized: "Drop the version again so DROP uploads the file and knows its checksum.")
            )
        }
        let branch = try await github.repository(tap).defaultBranch
        let existing = try await repository.file(tap, path: setup.path, ref: branch)
        let description = try? await github.repository(project).summary
        return try RegistryEditor.edit(
            setup,
            project: project,
            tag: release.tagName,
            asset: SelectedAsset(name: name, sha256: sha256),
            existing: existing,
            description: description
        )
    }

    // MARK: Writing

    /// Writes the edit: a branch with one commit and a pull request against the tap's default branch,
    /// or a commit to the default branch. Commits are made as the signed-in account with its private
    /// noreply address, without any trailer.
    public func publish(_ edit: RegistryEdit, mode: TapWriteMode) async throws -> GitHubPullRequest? {
        let identity = GitHubIdentity(user: try await github.currentUser())
        let base = try await github.repository(edit.repository).defaultBranch
        switch mode {
        case .directCommit:
            try await repository.putFile(edit.repository, path: edit.path, change: FileChange(
                message: edit.message, text: edit.newText, branch: base, sha: edit.blobSHA, identity: identity
            ))
            return nil
        case .pullRequest:
            let head = try await repository.branchHead(edit.repository, branch: base)
            try await repository.createBranch(edit.repository, name: edit.branch, from: head)
            try await repository.putFile(edit.repository, path: edit.path, change: FileChange(
                message: edit.message, text: edit.newText, branch: edit.branch, sha: edit.blobSHA, identity: identity
            ))
            return try await repository.openPullRequest(edit.repository, NewPullRequest(
                title: edit.message, head: edit.branch, base: base, body: edit.pullRequestBody
            ))
        }
    }

    /// Reads the file back where it was written and checks that it names the new version.
    public func verify(_ edit: RegistryEdit, mode: TapWriteMode) async throws {
        let ref: String
        switch mode {
        case .pullRequest: ref = edit.branch
        case .directCommit: ref = try await github.repository(edit.repository).defaultBranch
        }
        let file = try await repository.file(edit.repository, path: edit.path, ref: ref)
        guard edit.isApplied(in: file?.text) else {
            let repository = edit.repository.description
            throw DROPError(
                .rejected,
                whatHappened: String(localized: "\(edit.path) on \(repository) doesn't name \(edit.version)."),
                howToFix: String(localized: "Open the repository on GitHub and check the file.")
            )
        }
    }
}

extension DROPError {
    public static func registryNotSetUp(_ destination: Destination) -> DROPError {
        DROPError(
            .notConfigured,
            whatHappened: String(localized: "\(destination.title) isn't set up yet."),
            howToFix: String(localized: "Set it up under Destinations on the project page, or turn it off.")
        )
    }

    static func registryFileOwned(_ path: String, by owner: String) -> DROPError {
        DROPError(
            .alreadyExists,
            whatHappened: String(localized: "\(owner) already writes \(path), so DROP leaves it alone."),
            howToFix: String(localized: "Choose another file, or set this destination to External.")
        )
    }
}
