import DROPCore
import DROPGitHub
import DROPPersistence
import DROPTestFixtures
import Testing

@testable import DROPServices

@Suite("ProjectService")
struct ProjectServiceTests {
    let github = InMemoryGitHubService(repositories: [
        GitHubRepository(id: 42, fullName: "octocat/Hello-World"),
    ])
    let metadata = InMemoryMetadataStore()
    var service: ProjectService { ProjectService(github: github, metadata: metadata) }

    @Test func addsAProjectUnderGitHubsSpelling() async throws {
        let (project, repository) = try await service.addProject("https://github.com/OCTOCAT/hello-world.git")
        #expect(project.slug.description == "octocat/Hello-World")
        #expect(project.repositoryID == 42)
        #expect(repository.id == 42)
        #expect(try metadata.allProjects() == [project])
    }

    @Test func refusesInputThatIsNotARepository() async {
        await #expect(throws: DROPError.self) { try await service.addProject("not a repo") }
    }

    @Test func refusesTheSameRepositoryTwice() async throws {
        _ = try await service.addProject("octocat/Hello-World")
        await #expect(throws: DROPError.self) { try await service.addProject("octocat/hello-world") }
    }

    @Test func reportsRepositoriesGitHubDoesNotKnow() async {
        do {
            _ = try await service.addProject("octocat/missing")
            Issue.record("Expected an error")
        } catch {
            #expect((error as? DROPError)?.code == .notFound)
        }
    }

    @Test func followsARenameAndStoresTheNewName() async throws {
        let (project, _) = try await service.addProject("octocat/Hello-World")
        github.rename(id: 42, to: "octo-org/hello-world-app")

        let (updated, repository) = try await service.refresh(project)
        #expect(updated.id == project.id)
        #expect(updated.slug.description == "octo-org/hello-world-app")
        #expect(repository.fullName == "octo-org/hello-world-app")
        #expect(try metadata.allProjects().map(\.slug.description) == ["octo-org/hello-world-app"])
    }

    @Test func storesACaseOnlyRename() async throws {
        let (project, _) = try await service.addProject("octocat/Hello-World")
        github.rename(id: 42, to: "octocat/HELLO-WORLD")
        _ = try await service.refresh(project)
        #expect(try metadata.allProjects().map(\.slug.description) == ["octocat/HELLO-WORLD"])
    }

    @Test func learnsTheRepositoryIDOfProjectsAddedByName() async throws {
        let project = Fixtures.project("octocat/Hello-World")
        try metadata.saveProject(project)
        let (updated, _) = try await service.refresh(project)
        #expect(updated.repositoryID == 42)
        #expect(try metadata.allProjects().first?.repositoryID == 42)
    }
}
