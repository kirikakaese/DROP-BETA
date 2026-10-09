import DROPCore
import DROPGitHub
import DROPPersistence
import Foundation

/// What runs a project's releases today: its workflows, the automation found in them and in tool
/// configuration, and the ownership of each destination.
public struct AutomationReport: Sendable, Equatable {
    public let workflows: [WorkflowSummary]
    public let findings: [AutomationFinding]
    public let settings: [DestinationSetting]

    public func setting(for destination: Destination) -> DestinationSetting {
        settings.first { $0.destination == destination }
            ?? DestinationSetting(destination: destination, mode: .off)
    }

    /// The workflow that creates the GitHub Release when that is External, with how it starts.
    public var releaseAutomation: ReleaseAutomation? {
        let setting = setting(for: .githubRelease)
        guard setting.mode == .external, let owner = setting.owner,
            let summary = workflows.first(where: { $0.workflow.path == owner })
        else { return nil }
        return ReleaseAutomation(
            workflowID: summary.workflow.id,
            name: setting.ownerName ?? summary.workflow.name,
            startsOnTag: summary.triggers.tagPush
        )
    }

    /// Registries an existing automation publishes to.
    public var externalRegistries: [DestinationSetting] {
        settings.filter { $0.destination != .githubRelease && $0.mode == .external }
    }
}

/// Finds release automation in a repository and keeps the ownership you choose for each
/// destination. Reading only: detection never changes anything in the repository.
public struct AutomationService: Sendable {
    let workflows: WorkflowService
    let repository: any RepositoryServicing
    let metadata: any MetadataStoring

    public init(workflows: WorkflowService, repository: any RepositoryServicing, metadata: any MetadataStoring) {
        self.workflows = workflows
        self.repository = repository
        self.metadata = metadata
    }

    public func report(for project: Project, ref: String) async throws -> AutomationReport {
        let summaries = try await workflows.summaries(project.slug, ref: ref)
        var files: [String: String] = [:]
        for summary in summaries { files[summary.workflow.path] = summary.source }
        for path in AutomationDetector.configFiles {
            if let file = try? await repository.file(project.slug, path: path, ref: ref) { files[path] = file.text }
        }
        let findings = AutomationDetector.findings(in: files)
        let stored = (try? metadata.destinationSettings(projectID: project.id)) ?? []
        return AutomationReport(
            workflows: summaries,
            findings: findings,
            settings: AutomationDetector.settings(stored: stored, findings: findings)
        )
    }

    public func save(_ setting: DestinationSetting, for project: Project) throws {
        try metadata.saveDestinationSetting(setting, projectID: project.id)
    }
}
