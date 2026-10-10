import DROPCore
import DROPGitHub
import DROPPersistence
import DROPRegistries
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
    /// The run of the workflow that created the GitHub Release, when a workflow owns it.
    public let workflowRun: GitHubWorkflowRun?
    /// The pull requests that update tap and bucket files.
    public let registryPullRequests: [GitHubPullRequest]
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
    let repository: (any RepositoryServicing)?
    let actions: (any ActionsServicing)?
    let registries: RegistryService?
    let now: @Sendable () -> Date
    let sleep: @Sendable (Duration) async throws -> Void
    /// How often a release workflow's run is checked, and how long DROP waits for it at most.
    let pollInterval: Duration
    let workflowTimeout: TimeInterval

    public init(
        releases: any ReleaseServicing,
        metadata: any MetadataStoring,
        notifier: any DropNotifying,
        changelog: ChangelogService? = nil,
        repository: (any RepositoryServicing)? = nil,
        actions: (any ActionsServicing)? = nil,
        registries: RegistryService? = nil,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        pollInterval: Duration = .seconds(10),
        workflowTimeout: TimeInterval = 3_600
    ) {
        self.releases = releases
        self.metadata = metadata
        self.notifier = notifier
        self.changelog = changelog
        self.repository = repository
        self.actions = actions
        self.registries = registries
        self.now = now
        self.sleep = sleep
        self.pollInterval = pollInterval
        self.workflowTimeout = workflowTimeout
    }

    // MARK: Planning

    public func plan(_ request: DropRequest) async throws -> DropPlan {
        try Self.validate(request)
        let checksums = try Self.checksums(of: request.assets)
        var steps: [DropStep]
        if let automation = request.releaseAutomation {
            steps = try await automatedSteps(request, automation)
        } else {
            steps = try await managedSteps(request)
        }
        if let base = request.changelogBase {
            steps.append(.openChangelogPullRequest(tag: request.tagName, base: base))
        }
        steps += try await registrySteps(request)
        for setting in request.externalDestinations where setting.destination != .githubRelease {
            steps.append(.leaveToAutomation(destination: setting.destination, owner: setting.owner ?? "?"))
        }
        return DropPlan(request: request, steps: steps, checksums: checksums)
    }

    /// DROP creates the GitHub Release: tag, release (or its update), assets, checksums.
    private func managedSteps(_ request: DropRequest) async throws -> [DropStep] {
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
        return steps
    }

    /// A workflow creates the GitHub Release: DROP only pushes the tag (or starts the workflow on it),
    /// waits for the run and checks the result. It never creates the GitHub Release itself.
    private func automatedSteps(_ request: DropRequest, _ automation: ReleaseAutomation) async throws -> [DropStep] {
        let tag = request.tagName
        let tagExists = try await releases.tagExists(request.slug, tag: tag)
        if tagExists && automation.startsOnTag {
            throw DROPError.tagAlreadyPushed(tag, workflow: automation.name)
        }
        var steps: [DropStep] = []
        if !tagExists {
            steps.append(.pushTag(tag: tag, target: request.target.commitish))
        }
        if !automation.startsOnTag {
            steps.append(.dispatchWorkflow(name: automation.name, workflowID: automation.workflowID, tag: tag))
        }
        steps.append(.awaitWorkflow(name: automation.name, workflowID: automation.workflowID, tag: tag))
        steps.append(.verifyGitHubRelease(tag: tag, createdBy: automation.name))
        return steps
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
            release: release,
            record: record,
            unverified: run.unverified,
            changelogPullRequest: run.changelogPullRequest,
            workflowRun: run.workflowRun,
            registryPullRequests: run.registryPullRequests
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
        case .pushTag, .dispatchWorkflow, .awaitWorkflow, .verifyGitHubRelease, .leaveToAutomation:
            try await performAutomated(step, in: &run)
        case .updateRegistryFile, .verifyRegistryFile, .dispatchPublishWorkflow, .awaitPublishWorkflow:
            try await performRegistry(step, in: &run)
        }
    }

    /// The steps of a drop whose GitHub Release a workflow creates.
    private func performAutomated(_ step: DropStep, in run: inout DropRun) async throws {
        let slug = run.plan.request.slug
        switch step {
        case .pushTag(let tag, let target):
            guard let repository else { throw DROPError.somethingWentWrong }
            let sha = try await repository.commitSHA(slug, ref: target)
            try await repository.createTag(slug, name: tag, sha: sha)
        case .dispatchWorkflow(_, let workflowID, let tag):
            guard let actions else { throw DROPError.somethingWentWrong }
            try await actions.dispatch(slug, workflowID: workflowID, ref: tag)
        case .awaitWorkflow(let name, let workflowID, let tag):
            run.workflowRun = try await awaitRun(of: workflowID, named: name, tag: tag, slug: slug)
        case .verifyGitHubRelease(let tag, let createdBy):
            guard let release = try await releases.release(slug, tag: tag) else {
                throw DROPError(
                    .notFound,
                    whatHappened: String(localized: "\(createdBy) finished, but there is no GitHub Release \(tag).")
                )
            }
            run.release = release
        case .leaveToAutomation:
            break
        default:
            throw DROPError.somethingWentWrong
        }
    }

    /// Waits for the workflow's run on `tag` to finish. Fails when it fails or takes too long.
    private func awaitRun(of workflowID: Int64, named name: String, tag: String, slug: RepositorySlug) async throws
        -> GitHubWorkflowRun
    {
        guard let actions else { throw DROPError.somethingWentWrong }
        let start = now()
        while now().timeIntervalSince(start) < workflowTimeout {
            let runs = try await actions.runs(slug, workflowID: workflowID)
            if let found = runs.first(where: { $0.headBranch == tag }), found.isFinished {
                guard found.conclusion == "success" else {
                    throw DROPError(
                        .rejected,
                        whatHappened: String(localized: "\(name) failed (\(found.conclusion ?? found.status))."),
                        howToFix: String(localized: "Open the run on GitHub, fix it, then run it again on the tag.")
                    )
                }
                return found
            }
            try await sleep(pollInterval)
            try Task.checkCancellation()
        }
        throw DROPError(.network, whatHappened: String(localized: "\(name) didn't finish within an hour."))
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

// MARK: Registries

extension DropService {
    /// The registries DROP publishes once the GitHub Release exists. Betas and drafts stay out of taps
    /// and buckets; drafts aren't published anywhere. Checking a tap or bucket only reads.
    private func registrySteps(_ request: DropRequest) async throws -> [DropStep] {
        var steps: [DropStep] = []
        let version = AssetPattern.version(fromTag: request.tagName)
        for setup in request.registries where setup.isComplete && !request.isDraft {
            if setup.writesFile {
                guard !request.isPrerelease else { continue }
                guard let registries else { throw DROPError.somethingWentWrong }
                try await registries.check(setup, project: request.slug, ref: request.target.commitish)
                if request.releaseAutomation == nil, !request.assets.isEmpty {
                    let names = request.assets.map(\.name)
                    _ = try AssetPattern.select(from: names, pattern: setup.assetPattern, version: version)
                }
                steps.append(.updateRegistryFile(
                    destination: setup.destination,
                    repository: setup.repository,
                    path: setup.path,
                    viaPullRequest: setup.writeMode == .pullRequest
                ))
                steps.append(.verifyRegistryFile(
                    destination: setup.destination, repository: setup.repository, path: setup.path
                ))
            } else if let workflowID = setup.workflowID {
                let name = setup.workflowName ?? String(workflowID)
                let tag = request.tagName
                steps.append(.dispatchPublishWorkflow(
                    destination: setup.destination, name: name, workflowID: workflowID, tag: tag
                ))
                steps.append(.awaitPublishWorkflow(
                    destination: setup.destination, name: name, workflowID: workflowID, tag: tag
                ))
            }
        }
        return steps
    }

    /// The steps that publish to a registry, after the GitHub Release exists.
    private func performRegistry(_ step: DropStep, in run: inout DropRun) async throws {
        let request = run.plan.request
        guard let destination = step.registry,
            let setup = request.registries.first(where: { $0.destination == destination })
        else { throw DROPError.somethingWentWrong }
        switch step {
        case .updateRegistryFile:
            guard let registries else { throw DROPError.somethingWentWrong }
            // Read the release again: it now lists every asset with GitHub's checksum.
            guard let release = try await releases.release(request.slug, tag: request.tagName) ?? run.release else {
                throw DROPError.somethingWentWrong
            }
            let edit = try await registries.edit(
                setup, project: request.slug, release: release, localChecksums: run.expected
            )
            if let pullRequest = try await registries.publish(edit, mode: setup.writeMode) {
                run.registryPullRequests.append(pullRequest)
            }
            run.registryEdits[destination] = edit
        case .verifyRegistryFile:
            guard let registries, let edit = run.registryEdits[destination] else { throw DROPError.somethingWentWrong }
            try await registries.verify(edit, mode: setup.writeMode)
        case .dispatchPublishWorkflow(_, _, let workflowID, let tag):
            guard let actions else { throw DROPError.somethingWentWrong }
            try await actions.dispatch(request.slug, workflowID: workflowID, ref: tag)
        case .awaitPublishWorkflow(_, let name, let workflowID, let tag):
            _ = try await awaitRun(of: workflowID, named: name, tag: tag, slug: request.slug)
        default:
            throw DROPError.somethingWentWrong
        }
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
    var workflowRun: GitHubWorkflowRun?
    var registryEdits: [Destination: RegistryEdit] = [:]
    var registryPullRequests: [GitHubPullRequest] = []

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
    static func tagAlreadyPushed(_ tag: String, workflow: String) -> DROPError {
        DROPError(
            .alreadyExists,
            whatHappened: String(localized: "The tag \(tag) exists, and \(workflow) starts only when a tag is pushed."),
            howToFix: String(localized: "Choose a new version, or run \(workflow) on the tag by hand.")
        )
    }

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
