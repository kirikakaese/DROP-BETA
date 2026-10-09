import DROPCore
import DROPTestFixtures
import Testing

@testable import DROPServices

@Suite("ServiceContainer")
struct ServiceContainerTests {
    @Test func previewStartsWithTheGivenProjects() throws {
        let project = Fixtures.project("kirikakaese/SMP")
        let services = ServiceContainer.preview(projects: [project])
        #expect(try services.metadata.allProjects() == [project])
        #expect(services.startupIssue == nil)
    }
}
