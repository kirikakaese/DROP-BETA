import DROPCore
import DROPTestFixtures
import Foundation
import Testing

@testable import DROPGitHub

@Suite("Release requests")
struct ReleaseRequestTests {
    let slug = Fixtures.slug("octocat/Hello-World")

    @Test func decodesAReleaseWithAssetDigests() throws {
        let json = """
            {"id": 1, "tag_name": "v1.0.0", "name": "", "body": "Notes", "draft": false, "prerelease": true,
             "html_url": "https://github.com/octocat/Hello-World/releases/tag/v1.0.0",
             "target_commitish": "main", "created_at": "2026-10-01T12:00:00Z", "published_at": null,
             "assets": [{"id": 9, "name": "app.zip", "size": 1024,
                         "digest": "sha256:ABCDEF", "state": "uploaded",
                         "browser_download_url": "https://example.com/app.zip"}]}
            """
        let release = try GitHubJSON.decoder.decode(GitHubRelease.self, from: Data(json.utf8))
        #expect(release.title == "v1.0.0")
        #expect(release.isPrerelease)
        #expect(!release.isDraft)
        #expect(release.publishedAt == nil)
        #expect(release.assets.first?.sha256 == "abcdef")
        #expect(GitHubAsset(id: 1, name: "x", size: 0, digest: nil).sha256 == nil)
    }

    @Test func leavesUnsetFieldsOutOfTheBody() throws {
        let request = try GitHubRequest.updateRelease(slug, id: 5, ReleaseFields(name: "Title", isDraft: false))
        let body = try #require(request.body)
        let object = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
        #expect(Set(object.keys) == ["name", "draft"])
        #expect(request.method == .patch)
        #expect(request.path == "/repos/octocat/Hello-World/releases/5")
    }

    @Test func uploadsAssetsToTheUploadsHostWithTheFileAsBody() throws {
        let file = URL(filePath: "/tmp/app.zip")
        let request = GitHubRequest.uploadAsset(
            slug, releaseID: 5, name: "app 1.0.zip", file: file, contentType: "application/zip"
        )
        let urlRequest = try request.urlRequest(token: "t", userAgent: "DROP")
        #expect(urlRequest.url?.absoluteString
            == "https://uploads.github.com/repos/octocat/Hello-World/releases/5/assets?name=app%201.0.zip")
        #expect(urlRequest.value(forHTTPHeaderField: "Content-Type") == "application/zip")
        #expect(urlRequest.httpBody == nil)
        #expect(request.uploadFile == file)
    }

    @Test func encodesTagNamesInPaths() throws {
        let request = GitHubRequest.release(slug, tag: "app/v1.0#1")
        let url = try request.urlRequest(token: nil, userAgent: "DROP").url
        #expect(url?.absoluteString == "https://api.github.com/repos/octocat/Hello-World/releases/tags/app/v1.0%231")
        #expect(GitHubRequest.deleteTag(slug, tag: "v1.0").path == "/repos/octocat/Hello-World/git/refs/tags/v1.0")
    }

    @Test func clientSendsUploadsThroughTheTransportsUpload() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: "app.zip")
        try Data("zip".utf8).write(to: file)

        let transport = FakeTransport { _ in
            (201, [:], FakeTransport.json(#"{"id": 3, "name": "app.zip", "size": 3, "digest": "sha256:aa"}"#))
        }
        let client = GitHubClient(transport: transport, tokens: StaticTokens("t"), userAgent: "DROP")
        let request = GitHubRequest.uploadAsset(slug, releaseID: 5, name: "app.zip", file: file, contentType: "x")
        let asset = try await client.decode(GitHubAsset.self, from: request)
        #expect(asset.id == 3)
        #expect(transport.requests.first?.httpBody == Data("zip".utf8))
        #expect(transport.requests.first?.url?.host() == "uploads.github.com")
    }
}
