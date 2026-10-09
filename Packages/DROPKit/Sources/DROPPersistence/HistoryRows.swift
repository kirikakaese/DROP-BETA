import DROPCore
import Foundation
import GRDB

struct DropRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "dropRecord"

    var id: String
    var projectID: String
    var tagName: String
    var isDraft: Bool
    var isPrerelease: Bool
    var startedAt: Date
    var finishedAt: Date?
    var outcome: String?
    var failedStep: String?
    var releaseURL: String?

    init(_ record: DropRecord) {
        id = record.id.uuidString
        projectID = record.projectID.uuidString
        tagName = record.tagName
        isDraft = record.isDraft
        isPrerelease = record.isPrerelease
        startedAt = record.startedAt
        finishedAt = record.finishedAt
        outcome = record.outcome?.rawValue
        failedStep = record.failedStep
        releaseURL = record.releaseURL?.absoluteString
    }

    var record: DropRecord? {
        guard let id = UUID(uuidString: id), let projectID = UUID(uuidString: projectID) else { return nil }
        return DropRecord(
            id: id,
            projectID: projectID,
            tagName: tagName,
            isDraft: isDraft,
            isPrerelease: isPrerelease,
            startedAt: startedAt,
            finishedAt: finishedAt,
            outcome: outcome.flatMap(DropOutcome.init(rawValue:)),
            failedStep: failedStep,
            releaseURL: releaseURL.flatMap(URL.init(string:))
        )
    }
}

struct AuditRow: Codable, FetchableRecord, PersistableRecord {
    static let databaseTableName = "auditEntry"

    var id: String
    var projectID: String
    var dropID: String?
    var date: Date
    var message: String
    var succeeded: Bool

    init(_ entry: AuditEntry) {
        id = entry.id.uuidString
        projectID = entry.projectID.uuidString
        dropID = entry.dropID?.uuidString
        date = entry.date
        message = entry.message
        succeeded = entry.succeeded
    }

    var entry: AuditEntry? {
        guard let id = UUID(uuidString: id), let projectID = UUID(uuidString: projectID) else { return nil }
        return AuditEntry(
            id: id,
            projectID: projectID,
            dropID: dropID.flatMap(UUID.init(uuidString:)),
            date: date,
            message: message,
            succeeded: succeeded
        )
    }
}
