import DROPCore
import DROPServices
import DROPTestFixtures
import Foundation
import Testing

@testable import DROPUI

@MainActor
@Suite("ProjectsModel")
struct ProjectsModelTests {
    @Test func loadsProjectsAndDropsAStaleSelection() throws {
        let smp = Fixtures.project("kirikakaese/SMP")
        let services = ServiceContainer.preview(projects: [smp])
        let model = ProjectsModel(services: services)
        model.selection = UUID()

        model.load()
        #expect(model.projects == [smp])
        #expect(model.selection == nil)

        model.selection = smp.id
        #expect(model.selectedProject == smp)
    }

    @Test func showsTheStartupIssue() {
        var services = ServiceContainer.preview()
        services.startupIssue = .storageUnavailable(details: "disk I/O error")
        #expect(ProjectsModel(services: services).error?.code == .storage)
    }
}

@Suite("DropWording")
struct DropWordingTests {
    @Test func namesTheVersionWhenItIsKnown() {
        #expect(DropWording.actionTitle(version: nil) == "Drop")
        #expect(DropWording.actionTitle(version: "") == "Drop")
        #expect(DropWording.actionTitle(version: "1.2.3") == "Drop v1.2.3")
        #expect(DropWording.actionTitle(version: "v1.2.3-beta.1") == "Drop v1.2.3-beta.1")
        #expect(DropWording.menuTitle == "Drop…")
    }
}
