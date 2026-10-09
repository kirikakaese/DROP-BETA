import DROPCore
import DROPGitHub
import DROPPersistence
import Foundation

/// What happens while a plan runs, for the progress list.
public enum DropProgress: Sendable, Equatable {
    case started(DropStep)
    case finished(DropStep)
}

/// The end of a successful drop.
public struct DropResult: Sendable, Equatable {
    public let release: GitHubRelease
    public let record: DropRecord
    /// Assets GitHub reported no checksum for, so they couldn't be verified.
    public let unverified: [String]
    /// The pull request that adds the notes to CHANGELOG.md, if one was opened.
    public let changelogPullRequest: GitHubPullRequest?
}

/// Plans and performs drops: the tag, the GitHub Release, its assets and `SHA256SUMS.txt`.
///
/// Planning only reads from GitHub. Nothing is written before `execute` runs, which happens when
/// you press Drop on the plan.
public struct DropService: Sendable {
    let releases: any ReleaseServicing
    let metadata: any MetadataStoring
    let notifier: any DropNotifying
    let changelog: ChangelogService?
    let now: @Sendable () -> Date

    public init(
        releases: any ReleaseServicing,
        metadata: any MetadataStoring,
        notifier: any DropNotifying,
        changelog: ChangelogService? = nil,
        now: @escaping @Sendable () -> Date = { Date() }
    ) {
        self.releases = releases
        self.metadata = metadata
        self.notifier = notifier
        self.changelog = changelog
        self.now = now
    }

    // MARK: Planning

    public func plan(_ request: DropRequest) async throws -> DropPlan {
        try Self.validate(request)
        let checksums = try Self.checksums(of: request.assets)
        let slug = request.slug
        let existing = try await releases.release(slug, tag: request.tagName)
        var steps: [DropStep] = []
        if let existing {
            steps.append(.updateRelease(tag: request.tagName, releaseID: existing.id))
        } else if try await releases.tagExists(slug, tag: request.tagName) {
            steps.append(.createRelease(tag: request.tagName))
        } else if request.isDraft {
            steps.append(.createDraftRelease(tag: request.tagName, target: request.target.commitish))
        } else {
            steps.append(.createTagAndRelease(tag: request.tagName, target: request.target.commitish))
        }
        for asset in request.assets {
            if let old = existing?.assets.first(where: { $0.name == asset.name }) {
                steps.append(.replaceAsset(name: asset.name, existingID: old.id))
            } else {
                steps.append(.uploadAsset(name: asset.name))
            }
        }
        if request.includesChecksums && !request.assets.isEmpty {
            let old = existing?.assets.first { $0.name == Checksums.fileName }
            steps.append(.uploadChecksums(existingID: old?.id))
        }
        if !request.assets.isEmpty {
            steps.append(.verifyChecksums)
        }
        if let base = request.changelogBase {
            steps.append(.openChangelogPullRequest(tag: request.tagName, base: base))
        }
        return DropPlan(request: request, steps: steps, checksums: checksums)
    }

    static func validate(_ request: DropRequest) throws {
        guard TagName.isValid(request.tagName) else {
            throw DROPError(
                .invalidArgument,
                whatHappened: String(localized: "“\(request.tagName)” can't be used as a tag name."),
                howToFix: String(localized: "Use something like v1.2.3, without spaces or special characters.")
            )
        }
        if case .commit(let sha) = request.target, !Self.isCommitSHA(sha) {
            throw DROPError(
                .invalidArgument,
                whatHappened: String(localized: "“\(sha)” is not a commit SHA."),
                howToFix: String(localized: "Paste the full or abbreviated SHA (7 to 40 hex characters).")
            )
        }
        var names = Set<String>()
        for asset in request.assets {
            let reserved = request.includesChecksums && asset.name == Checksums.fileName
            guard !reserved, names.insert(asset.name).inserted else {
                throw DROPError(
                    .invalidArgument,
                    whatHappened: String(localized: "Two assets are named “\(asset.name)”."),
                    howToFix: String(localized: "Each asset on a GitHub Release needs its own name.")
                )
            }
        }
    }

    static func isCommitSHA(_ text: String) -> Bool {
        (7...40).contains(text.count) && text.allSatisfy(\.isHexDigit)
    }

    static func checksums(of assets: [DropAsset]) throws -> [String: String] {
        var checksums: [String: String] = [:]
        for asset in assets {
            do {
                checksums[asset.name] = try Checksums.sha256(of: asset.fileURL)
            } catch {
                throw DROPError(
                    .fileSystem,
                    whatHappened: String(localized: "DROP could not read “\(asset.fileURL.lastPathComponent)”."),
                    howToFix: String(localized: "Check that the file still exists, then try again."),
                    details: error.localizedDescription
                )
            }
        }
        return checksums
    }

    // MARK: Dropping

    /// Runs the plan step by step. On failure, the error names the step; dropping the same tag again
    /// continues, because existing assets are replaced.
    public func execute(
        _ plan: DropPlan,
        progress: @escaping @Sendable (DropProgress) async -> Void = { _ in }
    ) async throws -> DropResult {
        let request = plan.request
        var record = DropRecord(
            projectID: request.projectID,
            tagName: request.tagName,
            isDraft: request.isDraft,
            isPrerelease: request.isPrerelease,
            startedAt: now()
        )
        try? metadata.saveDropRecord(record)
        audit(record, String(localized: "Started dropping \(request.tagName)"), succeeded: true)

        var run = DropRun(plan: plan)
        for step in plan.steps {
            await progress(.started(step))
            do {
                try await perform(step, in: &run)
            } catch {
                let failure = DROPError.wrapping(error)
                record.finishedAt = now()
                record.outcome = .failed
                record.failedStep = step.title
                record.releaseURL = run.release?.htmlURL
                try? metadata.saveDropRecord(record)
                audit(record, "\(step.title): \(failure.whatHappened)", succeeded: false)
                await notifier.dropFailed(tag: request.tagName, project: request.slug.description, step: step.title)
                throw DROPError.dropFailed(at: step, because: failure)
            }
            audit(record, step.title, succeeded: true)
            await progress(.finished(step))
        }

        guard let release = run.release else { throw DROPError.somethingWentWrong }
        record.finishedAt = now()
        record.outcome = .dropped
        record.releaseURL = release.htmlURL
        try? metadata.saveDropRecord(record)
        audit(record, DropWording.doneTitle(version: request.tagName), succeeded: true)
        await notifier.dropped(tag: request.tagName, project: request.slug.description, url: release.htmlURL)
        return DropResult(
            release: release, record: record, unverified: run.unverified, changelogPullRequest: run.changelogPullRequest
        )
    }

    private func perform(_ step: DropStep, in run: inout DropRun) async throws {
        let request = run.plan.request
        let slug = request.slug
        switch step {
        case .createTagAndRelease, .createDraftRelease:
            run.release = try await releases.createRelease(slug, run.fields(includingTarget: true))
        case .createRelease:
            run.release = try await releases.createRelease(slug, run.fields(includingTarget: false))
        case .updateRelease(_, let id):
            var fields = run.fields(includingTarget: false)
            fields.tagName = nil
            run.release = try await releases.updateRelease(slug, id: id, fields)
        case .uploadAsset(let name):
            try await upload(name, in: &run)
        case .replaceAsset(let name, let existingID):
            try await releases.deleteAsset(slug, id: existingID)
            try await upload(name, in: &run)
        case .uploadChecksums(let existingID):
            try await uploadChecksums(replacing: existingID, in: &run)
        case .verifyChecksums:
            try verify(&run)
        case .openChangelogPullRequest(let tag, let base):
            guard let changelog else { throw DROPError.somethingWentWrong }
            run.changelogPullRequest = try await changelog.openPullRequest(
                slug, base: base, tag: tag, notes: Changelog.demotingHeadings(request.notes)
            )
        }
    }

    private func upload(_ name: String, in run: inout DropRun) async throws {
        guard let release = run.release, let asset = run.plan.request.assets.first(where: { $0.name == name }) else {
            throw DROPError.somethingWentWrong
        }
        let uploaded = try await releases.uploadAsset(
            run.plan.request.slug, releaseID: release.id, name: name, file: asset.fileURL
        )
        run.uploaded[name] = uploaded
    }

    private func uploadChecksums(replacing existingID: Int64?, in run: inout DropRun) async throws {
        guard let release = run.release else { throw DROPError.somethingWentWrong }
        let contents = Checksums.sumsFile(run.plan.checksums)
        let directory = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let file = directory.appending(path: Checksums.fileName)
        try Data(contents.utf8).write(to: file)
        if let existingID {
            try await releases.deleteAsset(run.plan.request.slug, id: existingID)
        }
        run.uploaded[Checksums.fileName] = try await releases.uploadAsset(
            run.plan.request.slug, releaseID: release.id, name: Checksums.fileName, file: file
        )
        run.expected[Checksums.fileName] = Checksums.sha256(of: Data(contents.utf8))
    }

    private func verify(_ run: inout DropRun) throws {
        for (name, expected) in run.expected.sorted(by: { $0.key < $1.key }) {
            guard let reported = run.uploaded[name]?.sha256 else {
                run.unverified.append(name)
                continue
            }
            guard reported == expected else {
                throw DROPError(
                    .rejected,
                    whatHappened: String(localized: "The checksum of “\(name)” on GitHub doesn't match your file."),
                    howToFix: String(localized: "Drop the same tag again to upload it once more."),
                    details: "expected \(expected), GitHub reported \(reported)"
                )
            }
        }
    }

    private func audit(_ record: DropRecord, _ message: String, succeeded: Bool) {
        let entry = AuditEntry(
            projectID: record.projectID, dropID: record.id, date: now(), message: message, succeeded: succeeded
        )
        try? metadata.appendAuditEntry(entry)
    }
}

/// What a running drop has done so far.
private struct DropRun {
    let plan: DropPlan
    var release: GitHubRelease?
    var uploaded: [String: GitHubAsset] = [:]
    var expected: [String: String]
    var unverified: [String] = []
    var changelogPullRequest: GitHubPullRequest?

    init(plan: DropPlan) {
        self.plan = plan
        expected = plan.checksums
    }

    func fields(includingTarget: Bool) -> ReleaseFields {
        let request = plan.request
        return ReleaseFields(
            tagName: request.tagName,
            targetCommitish: includingTarget ? request.target.commitish : nil,
            name: request.releaseTitle,
            body: request.notes,
            isDraft: request.isDraft,
            isPrerelease: request.isPrerelease
        )
    }
}

extension DROPError {
    static var dropAgainHint: String {
        String(localized: "Fix the problem, then drop the same tag again. Assets already uploaded are replaced.")
    }

    /// A step ran without what the steps before it should have produced.
    static var somethingWentWrong: DROPError {
        DROPError(.unexpected, whatHappened: String(localized: "Something went wrong."))
    }

    /// A drop stopped at `step`.
    public static func dropFailed(at step: DropStep, because error: DROPError) -> DROPError {
        DROPError(
            error.code,
            whatHappened: String(localized: "Drop failed at “\(step.title)”: \(error.whatHappened)"),
            howToFix: error.howToFix ?? dropAgainHint,
            details: error.details
        )
    }
}
