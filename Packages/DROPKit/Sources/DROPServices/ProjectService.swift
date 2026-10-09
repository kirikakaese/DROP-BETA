import DROPCore
import DROPGitHub
import DROPPersistence
import Foundation

/// Adding projects and keeping them in step with GitHub.
public struct ProjectService: Sendable {
    let github: any GitHubServicing
    let metadata: any MetadataStoring

    public init(github: any GitHubServicing, metadata: any MetadataStoring) {
        self.github = github
        self.metadata = metadata
    }

    /// Looks the repository up on GitHub and adds it under the name GitHub uses.
    public func addProject(_ input: String) async throws -> (Project, GitHubRepository) {
        guard let slug = RepositorySlug(parsing: input) else {
            throw DROPError(
                .invalidArgument,
                whatHappened: String(localized: "“\(input)” is not a GitHub repository."),
                howToFix: String(localized: "Enter it as owner/name or paste its github.com address.")
            )
        }
        let repository = try await github.repository(slug)
        let project = Project(slug: repository.slug ?? slug, repositoryID: repository.id)
        try metadata.saveProject(project)
        return (project, repository)
    }

    /// Fetches the repository and stores its new name if it was renamed or moved. Projects added by
    /// name only also get their repository ID here.
    public func refresh(_ project: Project) async throws -> (Project, GitHubRepository) {
        let repository: GitHubRepository
        if let id = project.repositoryID {
            repository = try await github.repository(id: id)
        } else {
            repository = try await github.repository(project.slug)
        }
        var updated = project
        if let current = repository.slug, current.description != project.slug.description {
            updated.slug = current
        }
        updated.repositoryID = repository.id
        if updated.slug.description != project.slug.description || updated.repositoryID != project.repositoryID {
            try metadata.saveProject(updated)
        }
        return (updated, repository)
    }

    public func removeProject(id: UUID) throws {
        try metadata.deleteProject(id: id)
    }
}
