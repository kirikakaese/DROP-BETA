import DROPCore
import DROPGitHub
import DROPServices
import Foundation
import Observation

/// One drop, from filling in the form through the "Ready to Drop" plan to the result.
@MainActor
@Observable
public final class DropModel {
    public enum Stage: Equatable {
        case editing
        case planning
        case ready(DropPlan)
        case dropping(DropPlan)
        case dropped(DropPlan, DropResult)
        case failed(DropPlan, DROPError)
    }

    public enum StepState: Equatable {
        case pending, running, done, failed
    }

    public let project: Project
    public private(set) var stage: Stage = .editing

    public var tagName = ""
    public var title = ""
    public var notes = ""
    public var targetBranch: String
    public var targetsCommit = false
    public var commitSHA = ""
    public var isDraft = false
    /// "Drop a Beta": a prerelease, suggested as the next `-beta.N`.
    public var isPrerelease = false {
        didSet { applySuggestion() }
    }
    /// The bump for the suggested version; starts at what the commits ask for.
    public var bump: VersionBump = .patch {
        didSet { applySuggestion() }
    }
    /// Whether to open a pull request that adds the notes to CHANGELOG.md.
    public var updatesChangelog = false
    /// The commits since the last release, once loaded.
    public private(set) var changes: UnreleasedChanges?
    private var suggestedTag: String?
    private var suggestedNotes: String?
    private let defaultBranch: String
    public private(set) var assets: [DropAsset] = []
    public var includesChecksums = true
    public private(set) var branches: [GitHubBranch] = []
    /// A problem with the form, shown above the buttons.
    public var formError: DROPError?
    /// The state of each step of the plan while and after it runs.
    public private(set) var stepStates: [StepState] = []

    private let services: ServiceContainer
    private let account: AccountModel
    private let onFinish: @MainActor () -> Void

    init(
        project: Project,
        repository: GitHubRepository?,
        services: ServiceContainer,
        account: AccountModel,
        onFinish: @escaping @MainActor () -> Void = {}
    ) {
        self.project = project
        self.services = services
        self.account = account
        self.onFinish = onFinish
        targetBranch = repository?.defaultBranch ?? "main"
        defaultBranch = repository?.defaultBranch ?? "main"
    }

    /// The sheet's title in each stage.
    public var headline: String {
        switch stage {
        case .editing, .planning: DropWording.actionTitle(version: tagName.isEmpty ? nil : tagName)
        case .ready: DropWording.readyTitle
        case .dropping: DropWording.progressTitle(version: tagName)
        case .dropped: DropWording.doneTitle(version: tagName)
        case .failed: DropWording.failedTitle
        }
    }

    public var canReview: Bool {
        stage == .editing && !tagName.trimmingCharacters(in: .whitespaces).isEmpty
            && (!targetsCommit || !commitSHA.isEmpty)
    }

    public var isRunning: Bool {
        if case .dropping = stage { true } else { false }
    }

    public var request: DropRequest {
        DropRequest(
            projectID: project.id,
            slug: project.slug,
            tagName: tagName.trimmingCharacters(in: .whitespaces),
            title: title,
            notes: notes,
            target: targetsCommit
                ? .commit(commitSHA.trimmingCharacters(in: .whitespaces)) : .branch(targetBranch),
            isDraft: isDraft,
            isPrerelease: isPrerelease,
            assets: assets,
            includesChecksums: includesChecksums,
            changelogBase: updatesChangelog ? (targetsCommit ? defaultBranch : targetBranch) : nil
        )
    }

    /// "Since v1.2.0: 2 features, 1 fix", for the version section of the form.
    public var suggestionSummary: String? {
        guard let changes else { return nil }
        let since = changes.since.map { String(localized: "Since \($0)") } ?? String(localized: "No release yet")
        let counts = String(localized: """
            \(changes.breakingCount) breaking, \(changes.count(ofType: "feat")) features, \
            \(changes.count(ofType: "fix")) fixes
            """)
        return "\(since): \(counts)"
    }

    /// Loads the commits since the last release and fills in the suggested tag and notes. Anything
    /// you already typed stays as it is.
    public func loadSuggestion() async {
        do {
            let branch = targetsCommit ? defaultBranch : targetBranch
            changes = try await services.changelog.unreleased(project.slug, branch: branch)
            if let changes { bump = changes.suggestion.bump }
            applySuggestion()
        } catch {
            formError = account.filter(error)
        }
    }

    private func applySuggestion() {
        guard let changes else { return }
        if tagName.isEmpty || tagName == suggestedTag {
            tagName = changes.suggestion.tagName(for: bump, beta: isPrerelease)
            suggestedTag = tagName
        }
        if notes.isEmpty || notes == suggestedNotes {
            notes = services.changelog.notes(changes, slug: project.slug, tag: tagName)
            suggestedNotes = notes
        }
    }

    public func loadBranches() async {
        do {
            branches = try await services.releases.branches(project.slug)
            if !branches.isEmpty, !branches.contains(where: { $0.name == targetBranch }) {
                targetBranch = branches[0].name
            }
        } catch {
            formError = account.filter(error)
        }
    }

    /// Adds files picked in the open panel. A file with the name of an existing asset replaces it.
    public func addAssets(_ urls: [URL]) {
        for url in urls {
            let size = (try? url.resourceValues(forKeys: [.fileSizeKey]))?.fileSize ?? 0
            let asset = DropAsset(fileURL: url, size: Int64(size))
            assets.removeAll { $0.name == asset.name }
            assets.append(asset)
        }
    }

    public func removeAsset(named name: String) {
        assets.removeAll { $0.name == name }
    }

    /// Builds the plan. This only reads from GitHub; nothing is written yet.
    public func review() async {
        guard canReview else { return }
        formError = nil
        stage = .planning
        do {
            let plan = try await services.drops.plan(request)
            stepStates = Array(repeating: .pending, count: plan.steps.count)
            stage = .ready(plan)
        } catch {
            formError = account.filter(error)
            stage = .editing
        }
    }

    public func backToEditing() {
        switch stage {
        case .ready, .failed:
            stage = .editing
        default:
            break
        }
    }

    /// Runs the reviewed plan. This is the only place a drop writes to GitHub.
    public func drop() async {
        guard case .ready(let plan) = stage else { return }
        stage = .dropping(plan)
        stepStates = Array(repeating: .pending, count: plan.steps.count)
        do {
            let result = try await services.drops.execute(plan) { [weak self] event in
                await self?.apply(event, in: plan)
            }
            stage = .dropped(plan, result)
        } catch {
            if let index = stepStates.firstIndex(of: .running) { stepStates[index] = .failed }
            let shown = account.filter(error) ?? .wrapping(error)
            stage = .failed(plan, shown)
        }
        onFinish()
    }

    private func apply(_ event: DropProgress, in plan: DropPlan) {
        switch event {
        case .started(let step):
            if let index = plan.steps.firstIndex(of: step) { stepStates[index] = .running }
        case .finished(let step):
            if let index = plan.steps.firstIndex(of: step) { stepStates[index] = .done }
        }
    }
}
