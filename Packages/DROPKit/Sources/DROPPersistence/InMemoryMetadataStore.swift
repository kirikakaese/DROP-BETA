import DROPCore
import Foundation
import os

/// `MetadataStoring` in memory, for previews and as the fallback when the database can't be opened.
public final class InMemoryMetadataStore: MetadataStoring, Sendable {
    private let projects: OSAllocatedUnfairLock<[Project]>

    public init(projects: [Project] = []) {
        self.projects = OSAllocatedUnfairLock(initialState: projects)
    }

    public func allProjects() throws -> [Project] {
        projects.withLock { $0 }.sorted { $0.addedAt < $1.addedAt }
    }

    public func saveProject(_ project: Project) throws {
        try projects.withLock { projects in
            if projects.contains(where: { $0.slug == project.slug && $0.id != project.id }) {
                throw DROPError.projectAlreadyAdded(project.slug)
            }
            if let index = projects.firstIndex(where: { $0.id == project.id }) {
                projects[index] = project
            } else {
                projects.append(project)
            }
        }
    }

    public func deleteProject(id: UUID) throws {
        projects.withLock { $0.removeAll { $0.id == id } }
    }
}
