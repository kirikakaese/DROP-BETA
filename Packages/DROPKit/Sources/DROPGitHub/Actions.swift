import DROPCore
import Foundation

/// A GitHub Actions workflow (`GET /repos/{owner}/{repo}/actions/workflows`).
public struct GitHubWorkflow: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int64
    public let name: String
    /// The file, like `.github/workflows/release.yml`.
    public let path: String
    public let state: String

    public init(id: Int64, name: String, path: String, state: String = "active") {
        self.id = id
        self.name = name
        self.path = path
        self.state = state
    }

    public var isActive: Bool { state == "active" }
}

/// One run of a workflow.
public struct GitHubWorkflowRun: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int64
    public let workflowID: Int64
    public let name: String?
    public let title: String?
    public let headBranch: String?
    public let headSHA: String
    public let event: String
    /// `queued`, `in_progress`, `completed`, …
    public let status: String
    /// `success`, `failure`, `cancelled`, … once completed.
    public let conclusion: String?
    public let runNumber: Int
    public let htmlURL: URL?
    public let createdAt: Date?

    public init(
        id: Int64,
        workflowID: Int64,
        name: String? = nil,
        title: String? = nil,
        headBranch: String? = "main",
        headSHA: String = "0000000",
        event: String = "push",
        status: String = "completed",
        conclusion: String? = "success",
        runNumber: Int = 1,
        htmlURL: URL? = nil,
        createdAt: Date? = nil
    ) {
        self.id = id
        self.workflowID = workflowID
        self.name = name
        self.title = title
        self.headBranch = headBranch
        self.headSHA = headSHA
        self.event = event
        self.status = status
        self.conclusion = conclusion
        self.runNumber = runNumber
        self.htmlURL = htmlURL
        self.createdAt = createdAt
    }

    public var isFinished: Bool { status == "completed" }

    enum CodingKeys: String, CodingKey {
        case id, name, event, status, conclusion
        case workflowID = "workflow_id"
        case title = "display_title"
        case headBranch = "head_branch"
        case headSHA = "head_sha"
        case runNumber = "run_number"
        case htmlURL = "html_url"
        case createdAt = "created_at"
    }
}

/// A job of a run, with its steps.
public struct GitHubJob: Decodable, Sendable, Equatable, Identifiable {
    public struct Step: Decodable, Sendable, Equatable {
        public let number: Int
        public let name: String
        public let status: String
        public let conclusion: String?

        public init(number: Int, name: String, status: String, conclusion: String?) {
            self.number = number
            self.name = name
            self.status = status
            self.conclusion = conclusion
        }
    }

    public let id: Int64
    public let name: String
    public let status: String
    public let conclusion: String?
    public let steps: [Step]

    public init(id: Int64, name: String, status: String, conclusion: String?, steps: [Step] = []) {
        self.id = id
        self.name = name
        self.status = status
        self.conclusion = conclusion
        self.steps = steps
    }

    enum CodingKeys: String, CodingKey { case id, name, status, conclusion, steps }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(Int64.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        status = try container.decode(String.self, forKey: .status)
        conclusion = try container.decodeIfPresent(String.self, forKey: .conclusion)
        steps = try container.decodeIfPresent([Step].self, forKey: .steps) ?? []
    }
}

/// A file set a run uploaded with `actions/upload-artifact`.
public struct GitHubArtifact: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int64
    public let name: String
    public let size: Int64
    public let isExpired: Bool

    public init(id: Int64, name: String, size: Int64, isExpired: Bool = false) {
        self.id = id
        self.name = name
        self.size = size
        self.isExpired = isExpired
    }

    enum CodingKeys: String, CodingKey {
        case id, name
        case size = "size_in_bytes"
        case isExpired = "expired"
    }
}

/// The wrappers the Actions API puts around its lists.
public struct WorkflowList: Decodable, Sendable {
    public let workflows: [GitHubWorkflow]
}

public struct WorkflowRunList: Decodable, Sendable {
    public let runs: [GitHubWorkflowRun]

    enum CodingKeys: String, CodingKey { case runs = "workflow_runs" }
}

public struct JobList: Decodable, Sendable {
    public let jobs: [GitHubJob]
}

public struct ArtifactList: Decodable, Sendable {
    public let artifacts: [GitHubArtifact]
}

extension GitHubRequest {
    public static func workflows(_ slug: RepositorySlug) -> GitHubRequest {
        GitHubRequest(path: repositoryPath(slug) + "/actions/workflows", query: [
            URLQueryItem(name: "per_page", value: "100"),
        ])
    }

    /// The newest runs, of one workflow or of all.
    public static func workflowRuns(
        _ slug: RepositorySlug,
        workflowID: Int64? = nil,
        perPage: Int = 20
    ) -> GitHubRequest {
        let path = workflowID.map { repositoryPath(slug) + "/actions/workflows/\($0)/runs" }
            ?? repositoryPath(slug) + "/actions/runs"
        return GitHubRequest(path: path, query: [URLQueryItem(name: "per_page", value: String(perPage))])
    }

    public static func workflowRun(_ slug: RepositorySlug, id: Int64) -> GitHubRequest {
        GitHubRequest(path: repositoryPath(slug) + "/actions/runs/\(id)")
    }

    public static func jobs(_ slug: RepositorySlug, runID: Int64) -> GitHubRequest {
        GitHubRequest(path: repositoryPath(slug) + "/actions/runs/\(runID)/jobs", query: [
            URLQueryItem(name: "per_page", value: "100"),
        ])
    }

    public static func artifacts(_ slug: RepositorySlug, runID: Int64) -> GitHubRequest {
        GitHubRequest(path: repositoryPath(slug) + "/actions/runs/\(runID)/artifacts", query: [
            URLQueryItem(name: "per_page", value: "100"),
        ])
    }

    /// Answers with a redirect to the log on GitHub's storage.
    public static func jobLogs(_ slug: RepositorySlug, jobID: Int64) -> GitHubRequest {
        GitHubRequest(path: repositoryPath(slug) + "/actions/jobs/\(jobID)/logs")
    }

    /// Answers with a redirect to the artifact's zip on GitHub's storage.
    public static func artifactZip(_ slug: RepositorySlug, artifactID: Int64) -> GitHubRequest {
        GitHubRequest(path: repositoryPath(slug) + "/actions/artifacts/\(artifactID)/zip")
    }

    /// `POST …/actions/workflows/{id}/dispatches`: runs a workflow that has `workflow_dispatch`.
    public static func dispatchWorkflow(_ slug: RepositorySlug, workflowID: Int64, ref: String) throws
        -> GitHubRequest
    {
        GitHubRequest(
            .post,
            path: repositoryPath(slug) + "/actions/workflows/\(workflowID)/dispatches",
            body: try JSONEncoder().encode(["ref": ref])
        )
    }
}
