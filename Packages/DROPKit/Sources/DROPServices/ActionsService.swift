import DROPCore
import DROPGitHub
import Foundation
import os

/// GitHub Actions of a repository: workflows and how they start, runs, jobs, logs and artifacts.
public protocol ActionsServicing: Sendable {
    func workflows(_ slug: RepositorySlug) async throws -> [GitHubWorkflow]
    /// The newest runs, of one workflow or of all.
    func runs(_ slug: RepositorySlug, workflowID: Int64?) async throws -> [GitHubWorkflowRun]
    func run(_ slug: RepositorySlug, id: Int64) async throws -> GitHubWorkflowRun
    func jobs(_ slug: RepositorySlug, runID: Int64) async throws -> [GitHubJob]
    /// The end of a job's log.
    func logTail(_ slug: RepositorySlug, jobID: Int64) async throws -> String
    func artifacts(_ slug: RepositorySlug, runID: Int64) async throws -> [GitHubArtifact]
    /// Downloads an artifact and unpacks it into `directory`; returns the files in it.
    func downloadArtifact(_ slug: RepositorySlug, artifactID: Int64, into directory: URL) async throws -> [URL]
    /// Starts a workflow that has `workflow_dispatch`, on `ref`.
    func dispatch(_ slug: RepositorySlug, workflowID: Int64, ref: String) async throws
}

/// `ActionsServicing` over the REST API.
public struct LiveActionsService: ActionsServicing {
    /// How much of a log to show.
    public static let logTailBytes = 64 * 1024

    let client: GitHubClient

    public init(client: GitHubClient) {
        self.client = client
    }

    public func workflows(_ slug: RepositorySlug) async throws -> [GitHubWorkflow] {
        try await client.decode(WorkflowList.self, from: .workflows(slug)).workflows
    }

    public func runs(_ slug: RepositorySlug, workflowID: Int64?) async throws -> [GitHubWorkflowRun] {
        try await client.decode(WorkflowRunList.self, from: .workflowRuns(slug, workflowID: workflowID)).runs
    }

    public func run(_ slug: RepositorySlug, id: Int64) async throws -> GitHubWorkflowRun {
        try await client.decode(GitHubWorkflowRun.self, from: .workflowRun(slug, id: id))
    }

    public func jobs(_ slug: RepositorySlug, runID: Int64) async throws -> [GitHubJob] {
        try await client.decode(JobList.self, from: .jobs(slug, runID: runID)).jobs
    }

    public func logTail(_ slug: RepositorySlug, jobID: Int64) async throws -> String {
        let location = try await client.redirectLocation(of: .jobLogs(slug, jobID: jobID))
        let data = try await client.fetchTail(of: location, bytes: Self.logTailBytes)
        return Self.text(from: data)
    }

    /// The tail can start in the middle of a UTF-8 character; skip up to three bytes to find a start.
    static func text(from data: Data) -> String {
        for skipped in 0...3 {
            if let text = String(bytes: data.dropFirst(skipped), encoding: .utf8) { return text }
        }
        return ""
    }

    public func artifacts(_ slug: RepositorySlug, runID: Int64) async throws -> [GitHubArtifact] {
        try await client.decode(ArtifactList.self, from: .artifacts(slug, runID: runID)).artifacts
    }

    public func downloadArtifact(_ slug: RepositorySlug, artifactID: Int64, into directory: URL) async throws -> [URL] {
        let location = try await client.redirectLocation(of: .artifactZip(slug, artifactID: artifactID))
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let zip = directory.appending(path: "artifact-\(artifactID).zip")
        try await client.download(location, to: zip)
        defer { try? FileManager.default.removeItem(at: zip) }
        return try ArtifactArchive.extract(zip, into: directory)
    }

    public func dispatch(_ slug: RepositorySlug, workflowID: Int64, ref: String) async throws {
        _ = try await client.send(.dispatchWorkflow(slug, workflowID: workflowID, ref: ref))
    }
}

/// Unpacks artifact zips with `ditto` and keeps only regular files inside the target folder, so a
/// crafted archive can't place files elsewhere or smuggle in links.
enum ArtifactArchive {
    static func extract(_ zip: URL, into directory: URL) throws -> [URL] {
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/ditto")
        process.arguments = ["-x", "-k", zip.path, directory.path]
        try process.run()
        process.waitUntilExit()
        guard process.terminationStatus == 0 else {
            throw DROPError(
                .fileSystem,
                whatHappened: String(localized: "DROP could not unpack the artifact."),
                details: "ditto exited with \(process.terminationStatus)"
            )
        }
        return try files(in: directory, excluding: zip)
    }

    static func files(in directory: URL, excluding zip: URL) throws -> [URL] {
        let root = directory.resolvingSymlinksInPath().path + "/"
        let keys: [URLResourceKey] = [.isRegularFileKey, .isSymbolicLinkKey]
        guard let enumerator = FileManager.default.enumerator(at: directory, includingPropertiesForKeys: keys) else {
            return []
        }
        var files: [URL] = []
        for case let url as URL in enumerator {
            let values = try url.resourceValues(forKeys: Set(keys))
            if values.isSymbolicLink == true {
                try FileManager.default.removeItem(at: url)
                continue
            }
            guard values.isRegularFile == true, url.lastPathComponent != zip.lastPathComponent else { continue }
            guard url.resolvingSymlinksInPath().path.hasPrefix(root) else { continue }
            files.append(url)
        }
        return files.sorted { $0.lastPathComponent < $1.lastPathComponent }
    }
}

/// `ActionsServicing` in memory, for tests and previews.
public final class InMemoryActionsService: ActionsServicing, Sendable {
    public struct State: Sendable {
        public var workflows: [GitHubWorkflow] = []
        public var runs: [GitHubWorkflowRun] = []
        public var jobs: [Int64: [GitHubJob]] = [:]
        public var logs: [Int64: String] = [:]
        public var artifacts: [Int64: [GitHubArtifact]] = [:]
        /// Artifact ID → file name → contents.
        public var artifactFiles: [Int64: [String: String]] = [:]
        /// Every dispatch as `workflowID@ref`.
        public var dispatches: [String] = []

        public init() {}
    }

    private let state: OSAllocatedUnfairLock<State>

    public init(_ initial: State = State()) {
        state = OSAllocatedUnfairLock(initialState: initial)
    }

    public var snapshot: State { state.withLock { $0 } }

    public func update(_ change: @Sendable (inout State) -> Void) {
        state.withLock { change(&$0) }
    }

    public func workflows(_ slug: RepositorySlug) async throws -> [GitHubWorkflow] {
        state.withLock { $0.workflows }
    }

    public func runs(_ slug: RepositorySlug, workflowID: Int64?) async throws -> [GitHubWorkflowRun] {
        state.withLock { state in
            state.runs.filter { workflowID == nil || $0.workflowID == workflowID }.sorted { $0.id > $1.id }
        }
    }

    public func run(_ slug: RepositorySlug, id: Int64) async throws -> GitHubWorkflowRun {
        try state.withLock { state in
            guard let run = state.runs.first(where: { $0.id == id }) else {
                throw DROPError.repositoryNotFound(details: nil)
            }
            return run
        }
    }

    public func jobs(_ slug: RepositorySlug, runID: Int64) async throws -> [GitHubJob] {
        state.withLock { $0.jobs[runID] ?? [] }
    }

    public func logTail(_ slug: RepositorySlug, jobID: Int64) async throws -> String {
        state.withLock { $0.logs[jobID] ?? "" }
    }

    public func artifacts(_ slug: RepositorySlug, runID: Int64) async throws -> [GitHubArtifact] {
        state.withLock { $0.artifacts[runID] ?? [] }
    }

    public func downloadArtifact(_ slug: RepositorySlug, artifactID: Int64, into directory: URL) async throws -> [URL] {
        let files = state.withLock { $0.artifactFiles[artifactID] ?? [:] }
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return try files.keys.sorted().map { name in
            let url = directory.appending(path: name)
            try Data((files[name] ?? "").utf8).write(to: url)
            return url
        }
    }

    public func dispatch(_ slug: RepositorySlug, workflowID: Int64, ref: String) async throws {
        state.withLock { $0.dispatches.append("\(workflowID)@\(ref)") }
    }
}
