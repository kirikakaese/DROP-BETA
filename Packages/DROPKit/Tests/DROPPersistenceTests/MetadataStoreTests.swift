import DROPCore
import DROPTestFixtures
import Foundation
import Testing

@testable import DROPPersistence

/// The same behavior is expected from the SQLite store and the in-memory fallback.
private func stores() throws -> [any MetadataStoring] {
    [try GRDBMetadataStore.inMemory(), InMemoryMetadataStore()]
}

@Suite("MetadataStore")
struct MetadataStoreTests {
    @Test(arguments: try stores())
    func savesListsAndDeletesProjects(_ store: any MetadataStoring) throws {
        let smp = Fixtures.project("kirikakaese/SMP")
        let drop = Fixtures.project("octocat/Hello-World", addedSecondsLater: 60)
        try store.saveProject(drop)
        try store.saveProject(smp)
        #expect(try store.allProjects() == [smp, drop])

        try store.deleteProject(id: smp.id)
        #expect(try store.allProjects() == [drop])
    }

    @Test(arguments: try stores())
    func updatesTheSlugAfterARename(_ store: any MetadataStoring) throws {
        var project = Fixtures.project("octocat/Hello-World")
        try store.saveProject(project)
        project.slug = Fixtures.slug("octocat/Hello-World-Renamed")
        try store.saveProject(project)
        #expect(try store.allProjects().map(\.slug.description) == ["octocat/Hello-World-Renamed"])
    }

    @Test(arguments: try stores())
    func refusesTheSameRepositoryTwiceIgnoringCase(_ store: any MetadataStoring) throws {
        try store.saveProject(Fixtures.project("kirikakaese/SMP"))
        #expect(throws: DROPError.self) {
            try store.saveProject(Fixtures.project("KIRIKAKAESE/smp"))
        }
        #expect(try store.allProjects().count == 1)
    }

    @Test(arguments: try stores())
    func keepsTheRepositoryID(_ store: any MetadataStoring) throws {
        var project = Fixtures.project("octocat/Hello-World")
        project.repositoryID = 1_296_269
        try store.saveProject(project)
        #expect(try store.allProjects().first?.repositoryID == 1_296_269)
    }

    @Test func createsTheDatabaseFileWithOwnerOnlyPermissions() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appending(path: "metadata.sqlite")

        try GRDBMetadataStore(url: url).saveProject(Fixtures.project("kirikakaese/SMP"))
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        #expect(permissions == 0o600)
        // Reopening runs the migrations again without losing data.
        #expect(try GRDBMetadataStore(url: url).allProjects().count == 1)
    }

    @Test(arguments: try stores())
    func keepsDropHistoryAndAuditLogPerProject(_ store: any MetadataStoring) throws {
        let project = Fixtures.project("octocat/Hello-World")
        let other = Fixtures.project("octocat/Spoon-Knife", addedSecondsLater: 1)
        try store.saveProject(project)
        try store.saveProject(other)

        var first = DropRecord(
            projectID: project.id, tagName: "v1.0.0", isDraft: false, isPrerelease: false,
            startedAt: Fixtures.referenceDate
        )
        try store.saveDropRecord(first)
        first.outcome = .dropped
        first.finishedAt = Fixtures.referenceDate.addingTimeInterval(30)
        first.releaseURL = URL(string: "https://github.com/octocat/Hello-World/releases/tag/v1.0.0")
        try store.saveDropRecord(first)
        let second = DropRecord(
            projectID: project.id, tagName: "v1.1.0", isDraft: true, isPrerelease: false,
            startedAt: Fixtures.referenceDate.addingTimeInterval(60), outcome: .failed, failedStep: "Upload app.zip"
        )
        try store.saveDropRecord(second)
        try store.saveDropRecord(DropRecord(
            projectID: other.id, tagName: "v9", isDraft: false, isPrerelease: false, startedAt: Fixtures.referenceDate
        ))

        #expect(try store.dropRecords(projectID: project.id) == [second, first])

        for (index, message) in ["one", "two", "three"].enumerated() {
            try store.appendAuditEntry(AuditEntry(
                projectID: project.id, dropID: first.id,
                date: Fixtures.referenceDate.addingTimeInterval(Double(index)), message: message, succeeded: true
            ))
        }
        #expect(try store.auditEntries(projectID: project.id, limit: 2).map(\.message) == ["three", "two"])
        #expect(try store.auditEntries(projectID: other.id, limit: 10).isEmpty)

        // Removing a project removes its history too.
        try store.deleteProject(id: project.id)
        #expect(try store.dropRecords(projectID: project.id).isEmpty)
        #expect(try store.auditEntries(projectID: project.id, limit: 10).isEmpty)
        #expect(try store.dropRecords(projectID: other.id).count == 1)
    }
}
