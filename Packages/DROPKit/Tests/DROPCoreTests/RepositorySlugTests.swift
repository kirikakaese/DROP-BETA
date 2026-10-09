import DROPTestFixtures
import Foundation
import Testing

@testable import DROPCore

@Suite("RepositorySlug")
struct RepositorySlugTests {
    @Test(arguments: [
        "octocat/Hello-World",
        "https://github.com/octocat/Hello-World",
        "https://github.com/octocat/Hello-World/",
        "https://github.com/octocat/Hello-World.git",
        "git@github.com:octocat/Hello-World.git",
        "  github.com/octocat/Hello-World\n",
    ])
    func parsesCommonForms(_ input: String) throws {
        let slug = try #require(RepositorySlug(parsing: input))
        #expect(slug.owner == "octocat")
        #expect(slug.name == "Hello-World")
        #expect(slug.description == "octocat/Hello-World")
    }

    @Test(arguments: [
        "", "octocat", "a/b/c", "/name", "owner/", "-owner/name", "owner-/name", "own--er/name",
        "owner/.", "owner/..", "owner/na me", "öwner/name", String(repeating: "a", count: 40) + "/name",
        "https://gitlab.com/owner/name",
    ])
    func rejectsInvalidInput(_ input: String) {
        #expect(RepositorySlug(parsing: input) == nil)
    }

    @Test func comparesCaseInsensitively() {
        let lower = Fixtures.slug("octocat/hello-world")
        let upper = Fixtures.slug("Octocat/HELLO-WORLD")
        #expect(lower == upper)
        #expect(Set([lower, upper]).count == 1)
        #expect(upper.description == "Octocat/HELLO-WORLD")
    }

    @Test func roundTripsThroughJSON() throws {
        let slug = Fixtures.slug("kirikakaese/SMP")
        let data = try JSONEncoder().encode(slug)
        // Encoded as a plain "owner/name" string (JSONEncoder may escape the slash, so decode it).
        #expect(try JSONDecoder().decode(String.self, from: data) == "kirikakaese/SMP")
        #expect(try JSONDecoder().decode(RepositorySlug.self, from: data) == slug)
        #expect(throws: DecodingError.self) {
            try JSONDecoder().decode(RepositorySlug.self, from: Data("\"not a slug\"".utf8))
        }
    }

    @Test func webURLPointsAtGitHub() {
        #expect(Fixtures.slug("kirikakaese/SMP").webURL.absoluteString == "https://github.com/kirikakaese/SMP")
    }

    @Test func appRepositoryIsAbsentOutsideTheApp() {
        // The test bundle has no DROPRepositorySlug key; the app gets it from Config/Repo.xcconfig.
        #expect(AppRepository.slug(in: Bundle(for: BundleMarker.self)) == nil)
    }
}

private final class BundleMarker {}
