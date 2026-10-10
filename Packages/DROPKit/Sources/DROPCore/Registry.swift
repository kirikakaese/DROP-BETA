import Foundation

/// How DROP changes a tap or bucket repository.
public enum TapWriteMode: String, CaseIterable, Sendable, Codable {
    /// Opens a pull request, so the change is reviewed before it reaches anyone (the default).
    case pullRequest
    /// Commits straight to the default branch.
    case directCommit

    public var title: String {
        switch self {
        case .pullRequest: String(localized: "Pull Request")
        case .directCommit: String(localized: "Direct Commit")
        }
    }
}

/// How DROP publishes a registry it manages for one project.
///
/// Homebrew and Scoop: DROP updates one file in a tap or bucket repository. GHCR and npm: DROP starts
/// a workflow in the project on the tag; it publishes with the workflow's own `GITHUB_TOKEN` or npm's
/// trusted publishing, so DROP never holds a registry token.
public struct RegistrySetup: Hashable, Sendable, Codable, Identifiable {
    public var id: Destination { destination }
    public let destination: Destination
    /// Homebrew and Scoop: the tap or bucket repository, like `kirikakaese/homebrew-tap`.
    public var repository: String
    /// Homebrew and Scoop: the file DROP updates, like `Casks/smp.rb` or `bucket/smp.json`.
    public var path: String
    /// Homebrew and Scoop: the asset the file points at. `{version}` stands for the version without
    /// a leading v, `*` for anything, like `SMP-{version}.dmg`.
    public var assetPattern: String
    public var writeMode: TapWriteMode
    /// Homebrew: the app a new cask installs, like `SMP.app`.
    public var appName: String
    /// GHCR and npm: the workflow DROP starts on the tag.
    public var workflowID: Int64?
    public var workflowName: String?

    public init(
        destination: Destination,
        repository: String = "",
        path: String = "",
        assetPattern: String = "",
        writeMode: TapWriteMode = .pullRequest,
        appName: String = "",
        workflowID: Int64? = nil,
        workflowName: String? = nil
    ) {
        self.destination = destination
        self.repository = repository
        self.path = path
        self.assetPattern = assetPattern
        self.writeMode = writeMode
        self.appName = appName
        self.workflowID = workflowID
        self.workflowName = workflowName
    }

    /// Whether DROP updates a file in a tap or bucket, as opposed to starting a workflow.
    public var writesFile: Bool {
        destination == .homebrewTap || destination == .scoopBucket
    }

    /// The tap or bucket repository, once it is a valid `owner/name`.
    public var repositorySlug: RepositorySlug? {
        RepositorySlug(parsing: repository.trimmingCharacters(in: .whitespaces))
    }

    /// Whether everything DROP needs is filled in.
    public var isComplete: Bool {
        if writesFile {
            return repositorySlug != nil && !path.trimmingCharacters(in: .whitespaces).isEmpty
                && !assetPattern.trimmingCharacters(in: .whitespaces).isEmpty
        }
        return workflowID != nil
    }

    /// A starting point for a project: the usual tap and bucket names and file layout.
    public static func suggested(for destination: Destination, slug: RepositorySlug) -> RegistrySetup {
        let token = slug.name.lowercased()
        switch destination {
        case .homebrewTap:
            return RegistrySetup(
                destination: destination,
                repository: "\(slug.owner)/homebrew-tap",
                path: "Casks/\(token).rb",
                assetPattern: "\(slug.name)-{version}.dmg",
                appName: "\(slug.name).app"
            )
        case .scoopBucket:
            return RegistrySetup(
                destination: destination,
                repository: "\(slug.owner)/scoop-bucket",
                path: "bucket/\(token).json",
                assetPattern: "\(slug.name)-{version}.zip"
            )
        case .githubRelease, .ghcr, .npm:
            return RegistrySetup(destination: destination)
        }
    }
}
