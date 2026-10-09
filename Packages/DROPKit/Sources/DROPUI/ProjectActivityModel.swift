import DROPCore
import DROPGitHub
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
    public private(set) var isLoading = false
    public var error: DROPError?

    private let services: ServiceContainer
    private let account: AccountModel

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
        loadLocal()
        guard account.isSignedIn else { return }
        isLoading = true
        defer { isLoading = false }
        do {
            releases = try await services.releases.releases(project.slug)
            unreleased = try await services.changelog.unreleased(project.slug, branch: branch)
        } catch {
            self.error = account.filter(error)
        }
    }

    public func loadLocal() {
        history = (try? services.metadata.dropRecords(projectID: project.id)) ?? []
        auditLog = (try? services.metadata.auditEntries(projectID: project.id, limit: 50)) ?? []
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

    private func log(_ message: String, succeeded: Bool) {
        let entry = AuditEntry(projectID: project.id, dropID: nil, date: Date(), message: message, succeeded: succeeded)
        try? services.metadata.appendAuditEntry(entry)
        loadLocal()
    }
}
