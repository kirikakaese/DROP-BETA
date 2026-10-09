import Foundation

/// A file to attach to a drop.
public struct DropAsset: Hashable, Sendable, Identifiable {
    public var id: String { name }
    public let fileURL: URL
    /// The name on GitHub; the file's name unless set otherwise.
    public let name: String
    public let size: Int64

    public init(fileURL: URL, name: String? = nil, size: Int64) {
        self.fileURL = fileURL
        self.name = name ?? fileURL.lastPathComponent
        self.size = size
    }
}

/// Where a new tag points.
public enum DropTarget: Hashable, Sendable {
    case branch(String)
    case commit(String)

    /// The value for the API's `target_commitish`.
    public var commitish: String {
        switch self {
        case .branch(let name), .commit(let name): name
        }
    }
}

/// The workflow that creates the GitHub Release when the GitHub Release is External.
public struct ReleaseAutomation: Hashable, Sendable {
    public let workflowID: Int64
    /// The file name, like `release.yml`.
    public let name: String
    /// Whether pushing the tag starts it; otherwise DROP starts it by hand on the tag.
    public let startsOnTag: Bool

    public init(workflowID: Int64, name: String, startsOnTag: Bool) {
        self.workflowID = workflowID
        self.name = name
        self.startsOnTag = startsOnTag
    }
}

/// Everything you chose for a drop, before anything is planned or sent.
public struct DropRequest: Hashable, Sendable {
    public var projectID: UUID
    public var slug: RepositorySlug
    public var tagName: String
    /// The GitHub Release's title; the tag name when empty.
    public var title: String
    public var notes: String
    public var target: DropTarget
    public var isDraft: Bool
    public var isPrerelease: Bool
    public var assets: [DropAsset]
    /// Whether to add `SHA256SUMS.txt` for the assets.
    public var includesChecksums: Bool
    /// The branch to open a CHANGELOG.md pull request against, or `nil` to leave CHANGELOG.md alone.
    public var changelogBase: String?
    /// Set when an existing workflow owns the GitHub Release: DROP then only pushes the tag (or
    /// starts the workflow) and watches.
    public var releaseAutomation: ReleaseAutomation?
    /// Registries an existing automation publishes to; DROP leaves them alone.
    public var externalDestinations: [DestinationSetting]

    public init(
        projectID: UUID,
        slug: RepositorySlug,
        tagName: String,
        title: String = "",
        notes: String = "",
        target: DropTarget,
        isDraft: Bool = false,
        isPrerelease: Bool = false,
        assets: [DropAsset] = [],
        includesChecksums: Bool = true,
        changelogBase: String? = nil,
        releaseAutomation: ReleaseAutomation? = nil,
        externalDestinations: [DestinationSetting] = []
    ) {
        self.projectID = projectID
        self.slug = slug
        self.tagName = tagName
        self.title = title
        self.notes = notes
        self.target = target
        self.isDraft = isDraft
        self.isPrerelease = isPrerelease
        self.assets = assets
        self.includesChecksums = includesChecksums
        self.changelogBase = changelogBase
        self.releaseAutomation = releaseAutomation
        self.externalDestinations = externalDestinations
    }

    public var releaseTitle: String {
        let trimmed = title.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? tagName : trimmed
    }
}

/// One thing a drop does. The plan lists them in order; nothing is sent before you press Drop.
public enum DropStep: Hashable, Sendable {
    /// Create the tag on `target` together with a new GitHub Release.
    case createTagAndRelease(tag: String, target: String)
    /// Create a draft GitHub Release; GitHub creates its tag on `target` when the draft is published.
    case createDraftRelease(tag: String, target: String)
    /// The tag exists already; create the GitHub Release for it.
    case createRelease(tag: String)
    /// A GitHub Release for the tag exists; update its title, notes and flags (dropping again).
    case updateRelease(tag: String, releaseID: Int64)
    case uploadAsset(name: String)
    /// An asset with this name exists on the GitHub Release and is replaced.
    case replaceAsset(name: String, existingID: Int64)
    /// Upload the generated `SHA256SUMS.txt` (replacing an existing one).
    case uploadChecksums(existingID: Int64?)
    /// Compare GitHub's checksums of the uploaded assets with the local ones.
    case verifyChecksums
    /// Open a pull request against `base` that adds the notes to CHANGELOG.md.
    case openChangelogPullRequest(tag: String, base: String)
    /// Create and push only the tag; a workflow creates the GitHub Release.
    case pushTag(tag: String, target: String)
    /// Start the workflow that creates the GitHub Release, on the tag.
    case dispatchWorkflow(name: String, workflowID: Int64, tag: String)
    /// Wait while the workflow builds and creates the GitHub Release.
    case awaitWorkflow(name: String, workflowID: Int64, tag: String)
    /// Check that the GitHub Release for the tag exists once the workflow finished.
    case verifyGitHubRelease(tag: String, createdBy: String)
    /// A registry an existing automation publishes to; DROP leaves it alone.
    case leaveToAutomation(destination: Destination, owner: String)

    /// A short description for the plan, the progress list and the history.
    public var title: String {
        switch self {
        case .createTagAndRelease(let tag, let target):
            String(localized: "Create tag \(tag) on \(target) and its GitHub Release")
        case .createDraftRelease(let tag, let target):
            String(localized: "Create a draft GitHub Release \(tag) (tagged on \(target) when published)")
        case .createRelease(let tag):
            String(localized: "Create the GitHub Release for the existing tag \(tag)")
        case .updateRelease(let tag, _):
            String(localized: "Update the existing GitHub Release \(tag)")
        case .uploadAsset(let name):
            String(localized: "Upload \(name)")
        case .replaceAsset(let name, _):
            String(localized: "Replace \(name)")
        case .uploadChecksums:
            String(localized: "Upload \(Checksums.fileName)")
        case .verifyChecksums:
            String(localized: "Verify the uploaded checksums")
        case .openChangelogPullRequest(let tag, let base):
            String(localized: "Open a pull request against \(base) that adds \(tag) to CHANGELOG.md")
        case .pushTag(let tag, let target):
            String(localized: "Create tag \(tag) on \(target) and push it")
        case .dispatchWorkflow(let name, _, let tag):
            String(localized: "Start \(name) on \(tag)")
        case .awaitWorkflow:
            String(localized: "Build and create the GitHub Release")
        case .verifyGitHubRelease(let tag, _):
            String(localized: "Check that the GitHub Release \(tag) exists")
        case .leaveToAutomation(let destination, _):
            String(localized: "Publish to \(destination.title)")
        }
    }
}

/// Who performs a step of the plan.
public enum Performer: Hashable, Sendable {
    case drop
    /// An existing automation, by file name.
    case automation(String)

    public var title: String {
        switch self {
        case .drop: "DROP"
        case .automation(let name): name
        }
    }
}

extension DropStep {
    public var performer: Performer {
        switch self {
        case .awaitWorkflow(let name, _, _): .automation(name)
        case .leaveToAutomation(_, let owner): .automation((owner as NSString).lastPathComponent)
        default: .drop
        }
    }

    /// Whether the step changes something on GitHub, as opposed to reading or waiting.
    public var writes: Bool {
        switch self {
        case .verifyChecksums, .awaitWorkflow, .verifyGitHubRelease, .leaveToAutomation: false
        default: true
        }
    }
}

/// The reviewed plan for one drop. Building it only reads from GitHub; executing it writes.
public struct DropPlan: Hashable, Sendable {
    public let request: DropRequest
    public let steps: [DropStep]
    /// SHA-256 per asset name, computed locally while planning.
    public let checksums: [String: String]
    /// Whether the plan drops a tag again that already has a GitHub Release.
    public var isRedrop: Bool {
        steps.contains { if case .updateRelease = $0 { true } else { false } }
    }

    public init(request: DropRequest, steps: [DropStep], checksums: [String: String]) {
        self.request = request
        self.steps = steps
        self.checksums = checksums
    }
}

/// How a drop ended, as kept in the history.
public enum DropOutcome: String, Codable, Sendable {
    case dropped
    case failed
}

/// One drop in a project's history. Contains no secrets.
public struct DropRecord: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let projectID: UUID
    public let tagName: String
    public let isDraft: Bool
    public let isPrerelease: Bool
    public let startedAt: Date
    public var finishedAt: Date?
    public var outcome: DropOutcome?
    /// The step that failed, as shown to the user.
    public var failedStep: String?
    public var releaseURL: URL?

    public init(
        id: UUID = UUID(),
        projectID: UUID,
        tagName: String,
        isDraft: Bool,
        isPrerelease: Bool,
        startedAt: Date,
        finishedAt: Date? = nil,
        outcome: DropOutcome? = nil,
        failedStep: String? = nil,
        releaseURL: URL? = nil
    ) {
        self.id = id
        self.projectID = projectID
        self.tagName = tagName
        self.isDraft = isDraft
        self.isPrerelease = isPrerelease
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.outcome = outcome
        self.failedStep = failedStep
        self.releaseURL = releaseURL
    }
}

/// One line of a project's audit log: something DROP did or tried on GitHub. Contains no secrets.
public struct AuditEntry: Identifiable, Hashable, Sendable {
    public let id: UUID
    public let projectID: UUID
    public let dropID: UUID?
    public let date: Date
    public let message: String
    public let succeeded: Bool

    public init(id: UUID = UUID(), projectID: UUID, dropID: UUID?, date: Date, message: String, succeeded: Bool) {
        self.id = id
        self.projectID = projectID
        self.dropID = dropID
        self.date = date
        self.message = message
        self.succeeded = succeeded
    }
}
