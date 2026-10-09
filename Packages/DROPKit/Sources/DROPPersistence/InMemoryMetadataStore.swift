import DROPCore
import Foundation
import os

/// `MetadataStoring` in memory, for previews and as the fallback when the database can't be opened.
public final class InMemoryMetadataStore: MetadataStoring, Sendable {
    private let projects: OSAllocatedUnfairLock<[Project]>
    private let drops = OSAllocatedUnfairLock<[DropRecord]>(initialState: [])
    private let audit = OSAllocatedUnfairLock<[AuditEntry]>(initialState: [])

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
        drops.withLock { $0.removeAll { $0.projectID == id } }
        audit.withLock { $0.removeAll { $0.projectID == id } }
    }

    public func dropRecords(projectID: UUID) throws -> [DropRecord] {
        drops.withLock { $0 }.filter { $0.projectID == projectID }.sorted { $0.startedAt > $1.startedAt }
    }

    public func saveDropRecord(_ record: DropRecord) throws {
        drops.withLock { drops in
            if let index = drops.firstIndex(where: { $0.id == record.id }) {
                drops[index] = record
            } else {
                drops.append(record)
            }
        }
    }

    public func auditEntries(projectID: UUID, limit: Int) throws -> [AuditEntry] {
        let entries = audit.withLock { $0 }.filter { $0.projectID == projectID }
        return Array(entries.reversed().prefix(limit))
    }

    public func appendAuditEntry(_ entry: AuditEntry) throws {
        audit.withLock { $0.append(entry) }
    }
}
