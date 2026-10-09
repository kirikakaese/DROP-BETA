import DROPCore
import DROPGitHub
import DROPServices
import Foundation
import Observation

/// The project list in the sidebar, the selected project and what GitHub says about each one.
@MainActor
@Observable
public final class ProjectsModel {
    public private(set) var projects: [Project] = []
    /// GitHub's view of each project, filled in by `refreshFromGitHub()`.
    public private(set) var repositories: [Project.ID: GitHubRepository] = [:]
    /// Projects GitHub no longer finds (deleted, or the account lost access).
    public private(set) var missing: Set<Project.ID> = []
    public var selection: Project.ID?
    /// The last error, shown as an alert.
    public var error: DROPError?

    /// Whether the Add Project sheet is open.
    public var isAddingProject = false
    public private(set) var yourRepositories: [GitHubRepository] = []
    public private(set) var isLoadingRepositories = false
    public private(set) var isAdding = false
    /// An error while adding, shown in the sheet.
    public var addError: DROPError?

    public let account: AccountModel
    private let services: ServiceContainer

    public init(services: ServiceContainer, account: AccountModel) {
        self.services = services
        self.account = account
        error = services.startupIssue
    }

    public var selectedProject: Project? {
        projects.first { $0.id == selection }
    }

    public var canAddProject: Bool { account.isSignedIn }

    /// The drop in progress or being prepared, shown as a sheet.
    public var currentDrop: DropModel?
    /// Changes whenever a drop finishes, so the project's activity reloads.
    public private(set) var dropsFinished = 0

    /// Whether Project → Drop… is available: a project is selected, GitHub still has it, and you're
    /// signed in.
    public var canDrop: Bool {
        guard let project = selectedProject else { return false }
        return account.isSignedIn && !missing.contains(project.id) && currentDrop == nil
    }

    /// Opens the drop sheet for the selected project.
    public func startDrop() {
        guard canDrop, let project = selectedProject else { return }
        currentDrop = DropModel(
            project: project,
            repository: repositories[project.id],
            services: services,
            account: account
        ) { [weak self] in
            self?.dropsFinished += 1
        }
    }

    public func activityModel(for project: Project) -> ProjectActivityModel {
        ProjectActivityModel(project: project, services: services, account: account)
    }

    public func load() {
        do {
            projects = try services.metadata.allProjects()
            if let selection, !projects.contains(where: { $0.id == selection }) {
                self.selection = nil
            }
        } catch {
            self.error = .wrapping(error)
        }
    }

    /// Asks GitHub about every project: follows renames and notes repositories that are gone.
    public func refreshFromGitHub() async {
        guard account.isSignedIn else { return }
        for project in projects {
            do {
                let (updated, repository) = try await services.projects.refresh(project)
                replace(updated)
                repositories[project.id] = repository
                missing.remove(project.id)
            } catch let error as DROPError where error.code == .notFound {
                missing.insert(project.id)
            } catch {
                // One failure (offline, session ended) applies to all projects; stop here.
                self.error = account.filter(error)
                return
            }
        }
    }

    public func loadYourRepositories() async {
        guard account.isSignedIn, !isLoadingRepositories else { return }
        isLoadingRepositories = true
        defer { isLoadingRepositories = false }
        do {
            yourRepositories = try await services.github.yourRepositories()
        } catch {
            addError = account.filter(error)
        }
    }

    /// Adds the repository named by `input` (owner/name or a github.com address). Returns whether it
    /// was added.
    @discardableResult
    public func addProject(_ input: String) async -> Bool {
        isAdding = true
        addError = nil
        defer { isAdding = false }
        do {
            let (project, repository) = try await services.projects.addProject(input)
            projects.append(project)
            repositories[project.id] = repository
            selection = project.id
            return true
        } catch {
            addError = account.filter(error)
            return false
        }
    }

    /// Removes the project from DROP. Nothing changes on GitHub.
    public func removeProject(id: Project.ID) {
        do {
            try services.projects.removeProject(id: id)
            projects.removeAll { $0.id == id }
            repositories[id] = nil
            missing.remove(id)
            if selection == id { selection = nil }
        } catch {
            self.error = .wrapping(error)
        }
    }

    /// Whether the repository is already a project (by GitHub ID or name).
    public func isAdded(_ repository: GitHubRepository) -> Bool {
        projects.contains { $0.repositoryID == repository.id || $0.slug == repository.slug }
    }

    private func replace(_ project: Project) {
        guard let index = projects.firstIndex(where: { $0.id == project.id }) else { return }
        projects[index] = project
    }
}
