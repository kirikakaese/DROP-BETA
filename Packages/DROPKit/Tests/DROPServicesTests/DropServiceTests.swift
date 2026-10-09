import DROPCore
import DROPGitHub
import DROPPersistence
import DROPTestFixtures
import Foundation
import Testing

@testable import DROPServices

@Suite("DropService")
struct DropServiceTests {
    let project = Fixtures.project("octocat/Hello-World")
    let releases = InMemoryReleaseService()
    let metadata = InMemoryMetadataStore()
    let notifier = RecordingDropNotifier()
    let files = TemporaryFiles()

    var service: DropService {
        DropService(releases: releases, metadata: metadata, notifier: notifier, now: { Fixtures.referenceDate })
    }

    func request(
        tag: String = "v1.2.3",
        assets: [String: String] = [:],
        draft: Bool = false,
        checksums: Bool = true
    ) throws -> DropRequest {
        let dropAssets = try assets.sorted { $0.key < $1.key }.map { name, contents in
            DropAsset(fileURL: try files.write(name, contents), size: Int64(contents.utf8.count))
        }
        return DropRequest(
            projectID: project.id,
            slug: project.slug,
            tagName: tag,
            title: "Hello 1.2.3",
            notes: "## Changes",
            target: .branch("main"),
            isDraft: draft,
            assets: dropAssets,
            includesChecksums: checksums
        )
    }

    // MARK: Planning

    @Test func plansANewTagWithAssetsChecksumsAndVerification() async throws {
        let plan = try await service.plan(request(assets: ["app.zip": "zip", "app.dmg": "dmg"]))
        #expect(plan.steps == [
            .createTagAndRelease(tag: "v1.2.3", target: "main"),
            .uploadAsset(name: "app.dmg"),
            .uploadAsset(name: "app.zip"),
            .uploadChecksums(existingID: nil),
            .verifyChecksums,
        ])
        #expect(plan.checksums["app.zip"] == Checksums.sha256(of: Data("zip".utf8)))
        #expect(!plan.isRedrop)
        // Planning writes nothing.
        #expect(releases.snapshot.log.isEmpty)
    }

    @Test func plansADraftAndAReleaseForAnExistingTag() async throws {
        let draft = try await service.plan(request(draft: true))
        #expect(draft.steps == [.createDraftRelease(tag: "v1.2.3", target: "main")])

        releases.update { $0.tags.insert("v1.2.3") }
        let existingTag = try await service.plan(request())
        #expect(existingTag.steps == [.createRelease(tag: "v1.2.3")])
    }

    @Test func plansARedropThatReplacesSameNamedAssets() async throws {
        releases.update { state in
            state.releases = [GitHubRelease(id: 7, tagName: "v1.2.3", assets: [
                GitHubAsset(id: 70, name: "app.zip", size: 1),
                GitHubAsset(id: 71, name: Checksums.fileName, size: 1),
                GitHubAsset(id: 72, name: "notes.txt", size: 1),
            ])]
        }
        let plan = try await service.plan(request(assets: ["app.zip": "new", "app.dmg": "dmg"]))
        #expect(plan.isRedrop)
        #expect(plan.steps == [
            .updateRelease(tag: "v1.2.3", releaseID: 7),
            .uploadAsset(name: "app.dmg"),
            .replaceAsset(name: "app.zip", existingID: 70),
            .uploadChecksums(existingID: 71),
            .verifyChecksums,
        ])
    }

    @Test func refusesBadTagsCommitsAndAssetNames() async throws {
        await #expect(throws: DROPError.self) { try await service.plan(request(tag: "v1 .2")) }

        var commit = try request()
        commit.target = .commit("not-a-sha")
        await #expect(throws: DROPError.self) { try await service.plan(commit) }

        let reserved = try request(assets: [Checksums.fileName: "x"])
        await #expect(throws: DROPError.self) { try await service.plan(reserved) }

        var missing = try request()
        missing.assets = [DropAsset(fileURL: URL(filePath: "/nonexistent/app.zip"), size: 0)]
        await #expect(throws: DROPError.self) { try await service.plan(missing) }
    }

    // MARK: Dropping

    @Test func dropsTagReleaseAssetsAndChecksums() async throws {
        let plan = try await service.plan(request(assets: ["app.zip": "zip"]))
        let events = EventRecorder()
        let result = try await service.execute(plan) { await events.record($0) }

        let state = releases.snapshot
        #expect(state.log == ["create v1.2.3", "upload app.zip", "upload SHA256SUMS.txt"])
        #expect(state.tags.contains("v1.2.3"))
        let release = try #require(state.releases.first)
        #expect(release.name == "Hello 1.2.3")
        #expect(release.body == "## Changes")
        #expect(release.targetCommitish == "main")
        #expect(release.assets.map(\.name) == ["app.zip", "SHA256SUMS.txt"])
        #expect(result.unverified.isEmpty)
        #expect(await events.events.count == plan.steps.count * 2)

        // History, audit log and notification.
        let record = try #require(try metadata.dropRecords(projectID: project.id).first)
        #expect(record.outcome == .dropped)
        #expect(record.releaseURL == release.htmlURL)
        let audit = try metadata.auditEntries(projectID: project.id, limit: 20)
        #expect(audit.first?.message == "Dropped v1.2.3")
        let allSucceeded = audit.allSatisfy(\.succeeded)
        #expect(allSucceeded)
        #expect(await notifier.notifications == ["dropped v1.2.3"])
    }

    @Test func theChecksumsFileListsEveryAsset() async throws {
        let uploads = UploadCapture()
        let capturing = CapturingReleases(base: releases, capture: uploads)
        let service = DropService(releases: capturing, metadata: metadata, notifier: notifier)
        let plan = try await service.plan(request(assets: ["b.zip": "bbb", "a.dmg": "aaa"]))
        _ = try await service.execute(plan)

        let sums = try #require(await uploads.contents[Checksums.fileName])
        #expect(sums == """
            \(Checksums.sha256(of: Data("aaa".utf8)))  a.dmg
            \(Checksums.sha256(of: Data("bbb".utf8)))  b.zip

            """)
    }

    @Test func droppingTheSameTagAgainReplacesAssetsInsteadOfFailing() async throws {
        let first = try await service.plan(request(assets: ["app.zip": "one"]))
        _ = try await service.execute(first)
        let second = try await service.plan(request(assets: ["app.zip": "two"]))
        _ = try await service.execute(second)

        let release = try #require(releases.snapshot.releases.first)
        #expect(releases.snapshot.releases.count == 1)
        #expect(release.assets.map(\.name).sorted() == ["SHA256SUMS.txt", "app.zip"])
        #expect(release.assets.first { $0.name == "app.zip" }?.sha256 == Checksums.sha256(of: Data("two".utf8)))
    }

    @Test func aFailedStepIsNamedRecordedAndNotified() async throws {
        releases.update { $0.failingWrite = "upload app.zip" }
        let plan = try await service.plan(request(assets: ["app.zip": "zip"]))
        do {
            _ = try await service.execute(plan)
            Issue.record("Expected the drop to fail")
        } catch let error as DROPError {
            #expect(error.whatHappened.contains("Upload app.zip"))
            #expect(error.code == .network)
        }
        let record = try #require(try metadata.dropRecords(projectID: project.id).first)
        #expect(record.outcome == .failed)
        #expect(record.failedStep == "Upload app.zip")
        let audit = try metadata.auditEntries(projectID: project.id, limit: 20)
        let hasFailure = audit.contains { !$0.succeeded }
        #expect(hasFailure)
        #expect(await notifier.notifications == ["failed v1.2.3 at Upload app.zip"])

        // Dropping again picks up where it stopped.
        let retry = try await service.plan(request(assets: ["app.zip": "zip"]))
        #expect(retry.isRedrop)
        _ = try await service.execute(retry)
        #expect(releases.snapshot.releases.first?.assets.count == 2)
    }

    @Test func aChecksumMismatchFailsTheDrop() async throws {
        releases.update { $0.corruptsUploads = true }
        let plan = try await service.plan(request(assets: ["app.zip": "zip"]))
        do {
            _ = try await service.execute(plan)
            Issue.record("Expected the verification to fail")
        } catch let error as DROPError {
            #expect(error.whatHappened.contains(DropStep.verifyChecksums.title))
        }
    }

    @Test func assetsWithoutADigestAreReportedAsUnverified() async throws {
        releases.update { $0.reportsDigests = false }
        let plan = try await service.plan(request(assets: ["app.zip": "zip"], checksums: false))
        let result = try await service.execute(plan)
        #expect(result.unverified == ["app.zip"])
    }
}

/// Files in a temporary folder, removed when the process ends.
final class TemporaryFiles: Sendable {
    let directory = FileManager.default.temporaryDirectory.appending(path: "DropServiceTests-\(UUID().uuidString)")

    func write(_ name: String, _ contents: String) throws -> URL {
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let url = directory.appending(path: name)
        try Data(contents.utf8).write(to: url)
        return url
    }
}

private actor EventRecorder {
    private(set) var events: [DropProgress] = []
    func record(_ event: DropProgress) { events.append(event) }
}

private actor UploadCapture {
    private(set) var contents: [String: String] = [:]
    func store(_ name: String, _ text: String) { contents[name] = text }
}

/// Passes everything to `base` and keeps a copy of each uploaded file's text.
private struct CapturingReleases: ReleaseServicing {
    let base: InMemoryReleaseService
    let capture: UploadCapture

    func releases(_ slug: RepositorySlug) async throws -> [GitHubRelease] { try await base.releases(slug) }
    func release(_ slug: RepositorySlug, tag: String) async throws -> GitHubRelease? {
        try await base.release(slug, tag: tag)
    }
    func tagExists(_ slug: RepositorySlug, tag: String) async throws -> Bool {
        try await base.tagExists(slug, tag: tag)
    }
    func branches(_ slug: RepositorySlug) async throws -> [GitHubBranch] { try await base.branches(slug) }
    func createRelease(_ slug: RepositorySlug, _ fields: ReleaseFields) async throws -> GitHubRelease {
        try await base.createRelease(slug, fields)
    }
    func updateRelease(_ slug: RepositorySlug, id: Int64, _ fields: ReleaseFields) async throws -> GitHubRelease {
        try await base.updateRelease(slug, id: id, fields)
    }
    func deleteRelease(_ slug: RepositorySlug, id: Int64) async throws { try await base.deleteRelease(slug, id: id) }
    func deleteTag(_ slug: RepositorySlug, tag: String) async throws { try await base.deleteTag(slug, tag: tag) }
    func deleteAsset(_ slug: RepositorySlug, id: Int64) async throws { try await base.deleteAsset(slug, id: id) }
    func uploadAsset(_ slug: RepositorySlug, releaseID: Int64, name: String, file: URL) async throws -> GitHubAsset {
        await capture.store(name, try String(contentsOf: file, encoding: .utf8))
        return try await base.uploadAsset(slug, releaseID: releaseID, name: name, file: file)
    }
}
