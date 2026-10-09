import DROPCore
import DROPTestFixtures
import Foundation
import Testing

@testable import DROPGitHub

@Suite("GitHubClient")
struct GitHubClientTests {
    static let repositoryJSON = """
        {"id": 42, "full_name": "octocat/Hello-World", "private": true, "archived": false,
         "default_branch": "main", "description": "My first repository", "pushed_at": "2026-10-01T12:00:00Z"}
        """

    @Test func decodesARepository() async throws {
        let transport = FakeTransport { _ in (200, [:], FakeTransport.json(Self.repositoryJSON)) }
        let client = GitHubClient(transport: transport, tokens: StaticTokens("token-1"), userAgent: "DROP")
        let repository = try await client.decode(GitHubRepository.self, from: .repository(id: 42))
        #expect(repository.id == 42)
        #expect(repository.slug == Fixtures.slug("octocat/Hello-World"))
        #expect(repository.isPrivate)
        #expect(repository.defaultBranch == "main")
        #expect(repository.summary == "My first repository")
        #expect(transport.requests.first?.url?.absoluteString == "https://api.github.com/repositories/42")
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer token-1")
    }

    @Test func retriesOnceWithAFreshTokenAfterA401() async throws {
        let transport = FakeTransport { request in
            request.value(forHTTPHeaderField: "Authorization") == "Bearer token-2"
                ? (200, [:], FakeTransport.json(Self.repositoryJSON))
                : (401, [:], FakeTransport.json(#"{"message": "Bad credentials"}"#))
        }
        let tokens = StaticTokens("token-1", replacement: "token-2")
        let client = GitHubClient(transport: transport, tokens: tokens, userAgent: "DROP")
        _ = try await client.send(.repository(id: 42))
        #expect(transport.requests.count == 2)
        #expect(await tokens.replacements == 1)
    }

    @Test func aSecond401EndsTheSessionWithoutRetryingAgain() async throws {
        let transport = FakeTransport { _ in (401, [:], FakeTransport.json(#"{"message": "Bad credentials"}"#)) }
        let tokens = StaticTokens("token-1", replacement: "token-2")
        let client = GitHubClient(transport: transport, tokens: tokens, userAgent: "DROP")
        await #expect(throws: DROPError.sessionExpired) { try await client.send(.currentUser) }
        #expect(transport.requests.count == 2)
    }

    static let errorCases: [(Int, [String: String], DROPError.Code)] = [
        (403, ["x-ratelimit-remaining": "0"], .rateLimited),
        (429, [:], .rateLimited),
        (404, [:], .notFound),
        (403, [:], .rejected),
        (422, [:], .rejected),
        (502, [:], .network),
    ]

    @Test(arguments: GitHubClientTests.errorCases)
    func mapsErrorResponses(status: Int, headers: [String: String], code: DROPError.Code) async {
        let transport = FakeTransport { _ in (status, headers, FakeTransport.json(#"{"message": "nope"}"#)) }
        let client = GitHubClient(transport: transport, tokens: StaticTokens("token-1"), userAgent: "DROP")
        do {
            _ = try await client.send(.currentUser)
            Issue.record("Expected an error")
        } catch let error as DROPError {
            #expect(error.code == code)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    /// One repository per page; pages 1 and 2 link to the next one.
    static func page(for request: URLRequest) -> (status: Int, headers: [String: String], body: Data) {
        let components = request.url.flatMap { URLComponents(url: $0, resolvingAgainstBaseURL: false) }
        let page = Int(components?.queryItems?.first { $0.name == "page" }?.value ?? "1") ?? 1
        var headers: [String: String] = [:]
        if page < 3 {
            headers["Link"] = """
                <https://api.github.com/user/repos?per_page=100&sort=pushed&page=\(page + 1)>; rel="next", \
                <https://api.github.com/user/repos?page=3>; rel="last"
                """
        }
        let body = """
            [{"id": \(page), "full_name": "octocat/repo\(page)", "private": false, "archived": false,
              "default_branch": "main"}]
            """
        return (200, headers, Data(body.utf8))
    }

    @Test func followsNextLinksAcrossPages() async throws {
        let transport = FakeTransport { Self.page(for: $0) }
        let client = GitHubClient(transport: transport, tokens: StaticTokens("token-1"), userAgent: "DROP")
        let all = try await client.decodeAllPages(GitHubRepository.self, from: .yourRepositories)
        #expect(all.map(\.id) == [1, 2, 3])
        #expect(transport.requests.count == 3)
    }

    @Test func ignoresNextLinksToOtherHosts() {
        #expect(GitHubResponse.nextPage(inLinkHeader: #"<https://evil.example/user/repos?page=2>; rel="next""#) == nil)
        let next = GitHubResponse.nextPage(inLinkHeader: #"<https://api.github.com/user/repos?page=2>; rel="next""#)
        #expect(next?.path == "/user/repos")
        #expect(next?.query == [URLQueryItem(name: "page", value: "2")])
    }
}
