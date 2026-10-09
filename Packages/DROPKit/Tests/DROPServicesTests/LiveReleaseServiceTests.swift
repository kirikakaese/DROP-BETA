import DROPCore
import DROPGitHub
import DROPTestFixtures
import Foundation
import Testing

@testable import DROPServices

@Suite("LiveReleaseService")
struct LiveReleaseServiceTests {
    let slug = Fixtures.slug("octocat/Hello-World")

    func service(_ responder: @escaping FakeTransport.Responder) -> (LiveReleaseService, FakeTransport) {
        let transport = FakeTransport(responder)
        let client = GitHubClient(transport: transport, tokens: StaticTokens("t"), userAgent: "DROP")
        return (LiveReleaseService(client: client), transport)
    }

    @Test func findsDraftsThatTheTagEndpointDoesNotKnow() async throws {
        let (releases, transport) = service { request in
            if request.url?.path().contains("/releases/tags/") == true {
                return (404, [:], FakeTransport.json(#"{"message": "Not Found"}"#))
            }
            return (200, [:], FakeTransport.json("""
                [{"id": 2, "tag_name": "v2.0.0", "draft": true, "prerelease": false, "assets": []},
                 {"id": 1, "tag_name": "v1.0.0", "draft": false, "prerelease": false, "assets": []}]
                """))
        }
        #expect(try await releases.release(slug, tag: "v2.0.0")?.id == 2)
        #expect(try await releases.release(slug, tag: "v3.0.0") == nil)
        #expect(transport.requests.count == 4)
    }

    @Test func tellsWhetherATagExists() async throws {
        let (releases, _) = service { request in
            request.url?.path().hasSuffix("/v1.0.0") == true
                ? (200, [:], FakeTransport.json(#"{"ref": "refs/tags/v1.0.0"}"#))
                : (404, [:], FakeTransport.json(#"{"message": "Not Found"}"#))
        }
        #expect(try await releases.tagExists(slug, tag: "v1.0.0"))
        #expect(try await releases.tagExists(slug, tag: "v2.0.0") == false)
    }

    @Test func uploadsWithAContentTypeFromTheFileExtension() async throws {
        let file = try TemporaryFiles().write("app.zip", "zip")
        let (releases, transport) = service { _ in
            (201, [:], FakeTransport.json(#"{"id": 3, "name": "app.zip", "size": 3}"#))
        }
        _ = try await releases.uploadAsset(slug, releaseID: 5, name: "app.zip", file: file)
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Content-Type") == "application/zip")
    }
}
