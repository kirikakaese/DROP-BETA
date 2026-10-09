import DROPCore
import DROPTestFixtures
import Foundation
import Testing

@testable import DROPGitHub

@Suite("Actions requests")
struct ActionsRequestTests {
    let slug = Fixtures.slug("octocat/Hello-World")

    @Test func decodesRunsJobsAndArtifacts() throws {
        let runs = try GitHubJSON.decoder.decode(WorkflowRunList.self, from: Data("""
            {"total_count": 1, "workflow_runs": [{"id": 7, "workflow_id": 2, "name": "Release",
             "display_title": "v1.0.0", "head_branch": "v1.0.0", "head_sha": "abc", "event": "push",
             "status": "in_progress", "conclusion": null, "run_number": 14,
             "html_url": "https://github.com/octocat/Hello-World/actions/runs/7",
             "created_at": "2026-10-01T12:00:00Z"}]}
            """.utf8))
        let run = try #require(runs.runs.first)
        #expect(run.title == "v1.0.0")
        #expect(!run.isFinished)
        #expect(run.conclusion == nil)

        let jobs = try GitHubJSON.decoder.decode(JobList.self, from: Data("""
            {"jobs": [{"id": 1, "name": "build", "status": "completed", "conclusion": "success",
             "steps": [{"number": 1, "name": "Set up job", "status": "completed", "conclusion": "success"}]}]}
            """.utf8))
        #expect(jobs.jobs.first?.steps.first?.name == "Set up job")

        let artifacts = try GitHubJSON.decoder.decode(ArtifactList.self, from: Data("""
            {"artifacts": [{"id": 5, "name": "build-linux", "size_in_bytes": 1024, "expired": false}]}
            """.utf8))
        #expect(artifacts.artifacts == [GitHubArtifact(id: 5, name: "build-linux", size: 1024)])
    }

    @Test func dispatchesOnARef() throws {
        let request = try GitHubRequest.dispatchWorkflow(slug, workflowID: 3, ref: "main")
        #expect(request.method == .post)
        #expect(request.path == "/repos/octocat/Hello-World/actions/workflows/3/dispatches")
        let body = try #require(request.body)
        #expect(try JSONDecoder().decode([String: String].self, from: body) == ["ref": "main"])
    }

    @Test func followsTheLogRedirectWithoutTheTokenAndReadsOnlyTheTail() async throws {
        let transport = FakeTransport { request in
            if request.url?.host() == "api.github.com" {
                return (302, ["Location": "https://results.example.net/log.txt?sig=1"], Data())
            }
            #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
            #expect(request.value(forHTTPHeaderField: "Range") == "bytes=-10")
            return (206, [:], Data("tail lines".utf8))
        }
        let client = GitHubClient(transport: transport, tokens: StaticTokens("t"), userAgent: "DROP")
        let location = try await client.redirectLocation(of: .jobLogs(slug, jobID: 9))
        #expect(location.absoluteString == "https://results.example.net/log.txt?sig=1")
        let data = try await client.fetchTail(of: location, bytes: 10)
        #expect(String(bytes: data, encoding: .utf8) == "tail lines")
        #expect(transport.requests.first?.value(forHTTPHeaderField: "Authorization") == "Bearer t")
    }

    @Test func refusesARedirectToPlainHTTP() async {
        let transport = FakeTransport { _ in (302, ["Location": "http://insecure.example/log"], Data()) }
        let client = GitHubClient(transport: transport, tokens: StaticTokens("t"), userAgent: "DROP")
        await #expect(throws: DROPError.self) { try await client.redirectLocation(of: .jobLogs(slug, jobID: 9)) }
    }
}
