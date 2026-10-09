import DROPCore
import DROPServices
import Foundation
import Observation

/// The project list in the sidebar and the selected project.
@MainActor
@Observable
public final class ProjectsModel {
    public private(set) var projects: [Project] = []
    public var selection: Project.ID?
    /// The last error, shown as an alert.
    public var error: DROPError?

    private let services: ServiceContainer

    public init(services: ServiceContainer) {
        self.services = services
        error = services.startupIssue
    }

    public var selectedProject: Project? {
        projects.first { $0.id == selection }
    }

    /// Whether Project → Drop… is available. Dropping needs a selected project and an account,
    /// which arrive with sign-in, so it stays off for now.
    public var canDrop: Bool { false }

    public func load() {
        do {
            projects = try services.metadata.allProjects()
            if let selection, !projects.contains(where: { $0.id == selection }) {
                self.selection = nil
            }
        } catch let error as DROPError {
            self.error = error
        } catch {
            self.error = .storageUnavailable(details: error.localizedDescription)
        }
    }
}
