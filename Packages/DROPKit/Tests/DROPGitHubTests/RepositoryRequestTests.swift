import DROPCore
import DROPTestFixtures
import Foundation
import Testing

@testable import DROPGitHub

@Suite("Repository requests")
struct RepositoryRequestTests {
    let slug = Fixtures.slug("octocat/Hello-World")

    @Test func decodesTagsCommitsAndFiles() throws {
        let tag = try JSONDecoder().decode(
            GitHubTag.self, from: Data(#"{"name": "v1.0.0", "commit": {"sha": "abc"}}"#.utf8)
        )
        #expect(tag == GitHubTag(name: "v1.0.0", sha: "abc"))

        let comparison = try JSONDecoder().decode(GitHubComparison.self, from: Data("""
            {"total_commits": 1, "commits": [{"sha": "def", "commit": {"message": "fix: a\\n\\nbody"}}]}
            """.utf8))
        #expect(comparison.commits == [GitHubCommit(sha: "def", message: "fix: a\n\nbody")])

        let encoded = Data("# Changelog\n".utf8).base64EncodedString()
        let file = try JSONDecoder().decode(GitHubFile.self, from: Data("""
            {"sha": "blob", "encoding": "base64", "content": "\(encoded)"}
            """.utf8))
        #expect(file.text == "# Changelog\n")
    }

    @Test func commitsWithTheNoreplyAddressAndBase64Content() throws {
        let identity = GitHubIdentity(user: GitHubUser(id: 252_577_764, login: "kirikakaese"))
        #expect(identity.email == "252577764+kirikakaese@users.noreply.github.com")
        let change = FileChange(
            message: "docs(changelog): add v1.0.0", text: "hi", branch: "changelog/v1.0.0", sha: nil, identity: identity
        )
        let request = try GitHubRequest.putFile(slug, path: "CHANGELOG.md", change: change)
        let body = try #require(request.body)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(object["content"] as? String == "aGk=")
        #expect(object["sha"] == nil)
        #expect((object["author"] as? [String: String])?["email"] == identity.email)
        #expect(request.method == .put)
        #expect(request.path == "/repos/octocat/Hello-World/contents/CHANGELOG.md")
    }

    @Test func comparesTagToBranch() throws {
        let request = GitHubRequest.compare(slug, base: "v1.0.0", head: "main")
        let url = try request.urlRequest(token: nil, userAgent: "DROP").url
        #expect(url?.path() == "/repos/octocat/Hello-World/compare/v1.0.0...main")
        #expect(url?.query() == "per_page=250")
    }
}
