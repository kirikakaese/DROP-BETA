import DROPCore
import Foundation
import GRDB

/// Persists the project list. Contains no secrets: tokens live in the Keychain.
public protocol MetadataStoring: Sendable {
    /// All projects, oldest first.
    func allProjects() throws -> [Project]
    /// Adds a project or updates the one with the same ID. Throws `alreadyExists` if another
    /// project has the same repository.
    func saveProject(_ project: Project) throws
    /// Deletes the project with its drop history and audit log.
    func deleteProject(id: UUID) throws

    /// The project's drops, newest first.
    func dropRecords(projectID: UUID) throws -> [DropRecord]
    /// Adds a drop or updates the one with the same ID.
    func saveDropRecord(_ record: DropRecord) throws
    /// The project's audit log, newest first.
    func auditEntries(projectID: UUID, limit: Int) throws -> [AuditEntry]
    func appendAuditEntry(_ entry: AuditEntry) throws

    /// The destinations you set for a project. Unset ones aren't listed.
    func destinationSettings(projectID: UUID) throws -> [DestinationSetting]
    func saveDestinationSetting(_ setting: DestinationSetting, projectID: UUID) throws
}

/// `MetadataStoring` backed by SQLite through GRDB.
public final class GRDBMetadataStore: MetadataStoring, Sendable {
    let database: DatabaseQueue

    /// Opens (and migrates) the store at `url`. The file is created with mode 0600.
    public convenience init(url: URL) throws {
        let queue = try DatabaseQueue(path: url.path)
        try FileManager.default.setAttributes([.posixPermissions: 0o600], ofItemAtPath: url.path)
        try self.init(database: queue)
    }

    /// The default store in Application Support.
    public static func live() throws -> GRDBMetadataStore {
        try GRDBMetadataStore(url: AppPaths.applicationSupportDirectory().appending(path: "metadata.sqlite"))
    }

    /// An in-memory store for tests and previews.
    public static func inMemory() throws -> GRDBMetadataStore {
        try GRDBMetadataStore(database: DatabaseQueue())
    }

    private init(database: DatabaseQueue) throws {
        self.database = database
        try Self.migrator.migrate(database)
    }

    static var migrator: DatabaseMigrator {
        var migrator = DatabaseMigrator()
        migrator.registerMigration("v1") { db in
            try db.create(table: "project") { table in
                table.primaryKey("id", .text)
                table.column("owner", .text).notNull().collate(.nocase)
                table.column("name", .text).notNull().collate(.nocase)
                table.column("addedAt", .datetime).notNull()
                table.uniqueKey(["owner", "name"])
            }
        }
        // GitHub's repository ID, so a renamed or moved repository is still found.
        migrator.registerMigration("v2") { db in
            try db.alter(table: "project") { table in
                table.add(column: "repositoryID", .integer)
            }
        }
        // Drop history and audit log. No secrets: tags, steps, outcomes and links only.
        migrator.registerMigration("v3") { db in
            try db.create(table: "dropRecord") { table in
                table.primaryKey("id", .text)
                table.column("projectID", .text).notNull().indexed()
                    .references("project", onDelete: .cascade)
                table.column("tagName", .text).notNull()
                table.column("isDraft", .boolean).notNull()
                table.column("isPrerelease", .boolean).notNull()
                table.column("startedAt", .datetime).notNull()
                table.column("finishedAt", .datetime)
                table.column("outcome", .text)
                table.column("failedStep", .text)
                table.column("releaseURL", .text)
            }
            try db.create(table: "auditEntry") { table in
                table.primaryKey("id", .text)
                table.column("projectID", .text).notNull().indexed()
                    .references("project", onDelete: .cascade)
                table.column("dropID", .text)
                table.column("date", .datetime).notNull()
                table.column("message", .text).notNull()
                table.column("succeeded", .boolean).notNull()
            }
        }
        // Who performs each destination (DROP, an existing automation, or nobody), per project.
        migrator.registerMigration("v4") { db in
            try db.create(table: "destinationSetting") { table in
                table.column("projectID", .text).notNull().references("project", onDelete: .cascade)
                table.column("destination", .text).notNull()
                table.column("mode", .text).notNull()
                table.column("owner", .text)
                table.primaryKey(["projectID", "destination"])
            }
        }
        return migrator
    }

    public func allProjects() throws -> [Project] {
        try database.read { db in
            try ProjectRecord.order(Column("addedAt"), Column("owner"), Column("name")).fetchAll(db)
                .compactMap(\.project)
        }
    }

    public func saveProject(_ project: Project) throws {
        try database.write { db in
            let duplicate = try ProjectRecord
                .filter(Column("owner") == project.slug.owner && Column("name") == project.slug.name)
                .filter(Column("id") != project.id.uuidString)
                .fetchCount(db)
            if duplicate > 0 { throw DROPError.projectAlreadyAdded(project.slug) }
            try ProjectRecord(project).save(db)
        }
    }

    public func deleteProject(id: UUID) throws {
        _ = try database.write { db in
            try ProjectRecord.deleteOne(db, key: id.uuidString)
        }
    }

    public func dropRecords(projectID: UUID) throws -> [DropRecord] {
        try database.read { db in
            try DropRow.filter(Column("projectID") == projectID.uuidString)
                .order(Column("startedAt").desc)
                .fetchAll(db)
                .compactMap(\.record)
        }
    }

    public func saveDropRecord(_ record: DropRecord) throws {
        try database.write { db in try DropRow(record).save(db) }
    }

    public func auditEntries(projectID: UUID, limit: Int) throws -> [AuditEntry] {
        try database.read { db in
            try AuditRow.filter(Column("projectID") == projectID.uuidString)
                .order(Column("date").desc)
                .limit(limit)
                .fetchAll(db)
                .compactMap(\.entry)
        }
    }

    public func appendAuditEntry(_ entry: AuditEntry) throws {
        try database.write { db in try AuditRow(entry).insert(db) }
    }

    public func destinationSettings(projectID: UUID) throws -> [DestinationSetting] {
        try database.read { db in
            try DestinationRow.filter(Column("projectID") == projectID.uuidString).fetchAll(db).compactMap(\.setting)
        }
    }

    public func saveDestinationSetting(_ setting: DestinationSetting, projectID: UUID) throws {
        try database.write { db in try DestinationRow(setting, projectID: projectID).save(db) }
    }
}

private struct ProjectRecord: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "project"

    var id: String
    var owner: String
    var name: String
    var repositoryID: Int64?
    var addedAt: Date

    init(_ project: Project) {
        id = project.id.uuidString
        owner = project.slug.owner
        name = project.slug.name
        repositoryID = project.repositoryID
        addedAt = project.addedAt
    }

    /// `nil` for a row that no longer parses (it is skipped rather than failing the whole list).
    var project: Project? {
        guard let uuid = UUID(uuidString: id), let slug = RepositorySlug(owner: owner, name: name) else {
            return nil
        }
        return Project(id: uuid, slug: slug, repositoryID: repositoryID, addedAt: addedAt)
    }
}
