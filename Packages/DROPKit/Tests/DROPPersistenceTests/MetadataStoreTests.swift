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
}
