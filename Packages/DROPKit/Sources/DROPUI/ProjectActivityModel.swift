import DROPCore
import DROPGitHub
import DROPRegistries
import DROPServices
import Foundation
import Observation

/// A project's GitHub Releases, its drop history and its audit log.
@MainActor
@Observable
public final class ProjectActivityModel {
    public let project: Project
    public private(set) var releases: [GitHubRelease] = []
    public private(set) var history: [DropRecord] = []
    public private(set) var auditLog: [AuditEntry] = []
    /// The commits since the last release on the default branch.
    public private(set) var unreleased: UnreleasedChanges?
    /// The automation found in the repository and who performs each destination.
    public private(set) var automation: AutomationReport?
    /// Switching an External destination to Managed waits here for a confirmation naming the
    /// automation that owns it.
    public var pendingTakeover: DestinationSetting?
    /// How DROP publishes each registry it manages, as saved.
    public private(set) var registrySetups: [Destination: RegistrySetup] = [:]
    /// The registry whose setup sheet is open.
    public var editingRegistry: RegistrySetup?
    /// A dry run: what DROP would write to a tap or bucket for the latest release.
    public var registryPreview: RegistryEdit?
    public private(set) var isPreviewing = false
    /// The pull request that adds a GHCR or npm publish workflow, once opened.
    public private(set) var proposedPublishWorkflow: GitHubPullRequest?
    /// Set when adding a workflow file needs signing in again with the `workflow` scope.
    public private(set) var needsWorkflowScope = false
    public private(set) var isLoading = false
    public var error: DROPError?

    private let services: ServiceContainer
    private let account: AccountModel
    private var branch = "main"

    init(project: Project, services: ServiceContainer, account: AccountModel) {
        self.project = project
        self.services = services
        self.account = account
    }

    /// The newest published release that isn't a prerelease, which GitHub marks "Latest".
    public var latest: GitHubRelease? {
        releases.first { !$0.isDraft && !$0.isPrerelease }
    }

    public func load(branch: String) async {
        self.branch = branch
        loadLocal()
        guard account.isSignedIn else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            releases = try await services.releases.releases(project.slug)
            unreleased = try await services.changelog.unreleased(project.slug, branch: branch)
            automation = try await services.automation.report(for: project, ref: branch)
        } catch {
            self.error = account.filter(error)
        }
    }

    public func loadLocal() {
        history = (try? services.metadata.dropRecords(projectID: project.id)) ?? []
        auditLog = (try? services.metadata.auditEntries(projectID: project.id, limit: 50)) ?? []
        registrySetups = Dictionary(
            services.registries.setups(for: project).map { ($0.destination, $0) },
            uniquingKeysWith: { _, last in last }
        )
    }

    /// Edits a GitHub Release's title, notes and flags.
    @discardableResult
    public func update(_ release: GitHubRelease, _ fields: ReleaseFields) async -> Bool {
        do {
            let updated = try await services.releases.updateRelease(project.slug, id: release.id, fields)
            if let index = releases.firstIndex(where: { $0.id == release.id }) { releases[index] = updated }
            log(String(localized: "Edited the GitHub Release \(release.tagName)"), succeeded: true)
            return true
        } catch {
            log(String(localized: "Editing the GitHub Release \(release.tagName) failed"), succeeded: false)
            self.error = account.filter(error)
            return false
        }
    }

    /// Deletes a GitHub Release and, if asked, its tag.
    public func delete(_ release: GitHubRelease, includingTag: Bool) async {
        do {
            try await services.releases.deleteRelease(project.slug, id: release.id)
            releases.removeAll { $0.id == release.id }
            log(String(localized: "Deleted the GitHub Release \(release.tagName)"), succeeded: true)
            if includingTag && !release.isDraft {
                try await services.releases.deleteTag(project.slug, tag: release.tagName)
                log(String(localized: "Deleted the tag \(release.tagName)"), succeeded: true)
            }
        } catch {
            log(String(localized: "Deleting \(release.tagName) failed"), succeeded: false)
            self.error = account.filter(error)
        }
    }

    /// Changes who performs a destination. Taking over from an automation needs `confirmTakeover()`.
    public func setMode(_ mode: OwnershipMode, for destination: Destination) {
        guard let current = automation?.setting(for: destination), current.mode != mode else { return }
        var setting = current
        setting.mode = mode
        if mode == .external, setting.owner == nil {
            setting.owner = automation?.findings.first { $0.destination == destination }?.owner
        }
        if current.mode == .external && mode == .managed {
            pendingTakeover = setting
        } else {
            apply(setting)
        }
    }

    public func confirmTakeover() {
        guard let setting = pendingTakeover else { return }
        pendingTakeover = nil
        apply(setting)
    }

    /// The saved setup for a registry, or a suggestion to start from.
    public func setup(for destination: Destination) -> RegistrySetup {
        registrySetups[destination] ?? .suggested(for: destination, slug: project.slug)
    }

    /// The workflows DROP can start on a tag, for GHCR and npm.
    public var dispatchableWorkflows: [WorkflowSummary] {
        automation?.workflows.filter(\.triggers.dispatch) ?? []
    }

    public func editSetup(for destination: Destination) {
        proposedPublishWorkflow = nil
        needsWorkflowScope = false
        editingRegistry = setup(for: destination)
    }

    public func saveSetup(_ setup: RegistrySetup) {
        do {
            try services.registries.save(setup, for: project)
            registrySetups[setup.destination] = setup
            editingRegistry = nil
            log(String(localized: "Saved how DROP publishes to \(setup.destination.title)"), succeeded: true)
        } catch {
            self.error = .wrapping(error)
        }
    }

    /// A dry run for the latest release: computes the change to the tap or bucket file and writes
    /// nothing.
    public func preview(_ destination: Destination) async {
        guard let release = latest else {
            error = DROPError(.notFound, whatHappened: String(localized: "There is no release to try this with yet."))
            return
        }
        isPreviewing = true
        defer { isPreviewing = false }
        do {
            registryPreview = try await services.registries.edit(
                setup(for: destination), project: project.slug, release: release
            )
        } catch {
            self.error = account.filter(error)
        }
    }

    /// Opens a pull request that adds the GHCR or npm publish workflow. Asks to sign in again first
    /// when the account doesn't have the `workflow` scope.
    public func proposePublishWorkflow(for destination: Destination) async {
        guard await account.canChangeWorkflows() else {
            needsWorkflowScope = true
            return
        }
        needsWorkflowScope = false
        do {
            proposedPublishWorkflow = try await services.workflows.proposePublishWorkflow(
                for: destination, project.slug, base: branch
            )
            let message = String(localized: "Opened a pull request that adds a workflow for \(destination.title)")
            log(message, succeeded: true)
        } catch {
            self.error = account.filter(error)
        }
    }

    public func grantWorkflowScope() {
        account.signIn(scopes: OAuthConfiguration.workflowScopes)
    }

    private func apply(_ setting: DestinationSetting) {
        do {
            try services.automation.save(setting, for: project)
            if let report = automation {
                automation = AutomationReport(
                    workflows: report.workflows,
                    findings: report.findings,
                    settings: report.settings.map { $0.destination == setting.destination ? setting : $0 }
                )
            }
            log(String(localized: "\(setting.destination.title) is now \(setting.mode.title)"), succeeded: true)
        } catch {
            self.error = .wrapping(error)
        }
    }

    private func log(_ message: String, succeeded: Bool) {
        let entry = AuditEntry(projectID: project.id, dropID: nil, date: Date(), message: message, succeeded: succeeded)
        try? services.metadata.appendAuditEntry(entry)
        loadLocal()
    }
}
