import DROPTestFixtures
import Foundation
import Testing

@testable import DROPGitHub

@Suite("GitHubRequest")
struct GitHubRequestTests {
    @Test func setsTheHeadersEveryCallNeeds() throws {
        let request = try GitHubRequest.repository(Fixtures.slug("octocat/Hello-World"))
            .urlRequest(token: "token-value", userAgent: "DROP/0.1.0")
        #expect(request.url?.absoluteString == "https://api.github.com/repos/octocat/Hello-World")
        #expect(request.httpMethod == "GET")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/vnd.github+json")
        #expect(request.value(forHTTPHeaderField: "X-GitHub-Api-Version") == "2022-11-28")
        #expect(request.value(forHTTPHeaderField: "User-Agent") == "DROP/0.1.0")
        #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer token-value")
        #expect(request.value(forHTTPHeaderField: "Content-Type") == nil)
    }

    @Test func leavesOutAuthorizationWithoutAToken() throws {
        let request = try GitHubRequest(path: "/meta").urlRequest(token: nil, userAgent: "DROP")
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
    }

    @Test func encodesQueryAndBody() throws {
        let body = Data(#"{"tag_name":"v1.2.3"}"#.utf8)
        let request = try GitHubRequest(
            .post,
            path: "/repos/o/r/releases",
            query: [URLQueryItem(name: "per_page", value: "100")],
            body: body
        ).urlRequest(token: nil, userAgent: "DROP")
        #expect(request.url?.absoluteString == "https://api.github.com/repos/o/r/releases?per_page=100")
        #expect(request.httpMethod == "POST")
        #expect(request.httpBody == body)
        #expect(request.value(forHTTPHeaderField: "Content-Type") == "application/json")
    }

    @Test(arguments: ["meta", "https://evil.example/x", "//evil.example/x"])
    func refusesPathsThatLeaveTheAPI(_ path: String) {
        #expect(throws: (any Error).self) {
            try GitHubRequest(path: path).urlRequest(token: "token-value", userAgent: "DROP")
        }
    }
}
