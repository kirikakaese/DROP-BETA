import DROPCore
import DROPGitHub
import Foundation

/// Finds the automation that already writes a tap or bucket file, so DROP never touches it.
public enum TapOwnership {
    /// The first of `files` (path → text, workflows of the project and of the tap) that mentions
    /// `path`, by its full path or as `/name.ext`.
    public static func owner(of path: String, in files: [String: String]) -> String? {
        let name = "/" + (path as NSString).lastPathComponent
        return files.keys.sorted().first { file in
            guard let text = files[file] else { return false }
            return text.contains(path) || text.contains(name)
        }
    }
}

/// The change to one registry file for one version: what DROP shows in a dry run and writes when you
/// drop.
public struct RegistryEdit: Hashable, Sendable, Identifiable {
    public let destination: Destination
    public let repository: RepositorySlug
    public let path: String
    /// The file as it is, or `nil` when DROP creates it.
    public let oldText: String?
    /// The file's blob SHA, needed to update it.
    public let blobSHA: String?
    public let newText: String
    public let version: String
    public let assetName: String
    public let sha256: String
    /// Homebrew: `smp 1.2.3`. Scoop: `smp: Update to version 1.2.3`.
    public let message: String

    public var id: String { "\(repository)/\(path)@\(version)" }

    /// The token or app name: the file name without its extension, like `smp`.
    public var token: String {
        ((path as NSString).lastPathComponent as NSString).deletingPathExtension
    }

    /// The branch a pull request comes from, like `drop/smp-1.2.3`.
    public var branch: String { "drop/\(token)-\(version)" }

    public var isNew: Bool { oldText == nil }

    /// Whether `text` (read back after writing) is this edit.
    public func isApplied(in text: String?) -> Bool {
        guard let text else { return false }
        return text.contains(sha256) && text.contains(version)
    }

    /// The pull request's description.
    public var pullRequestBody: String {
        """
        Updates `\(path)` to \(version).

        - Asset: `\(assetName)`
        - SHA-256: `\(sha256)`

        """
    }
}

/// The release asset a registry file points at.
public struct SelectedAsset: Hashable, Sendable {
    public let name: String
    public let sha256: String

    public init(name: String, sha256: String) {
        self.name = name
        self.sha256 = sha256
    }
}

/// Builds the edit for a registry file. Reads nothing itself: the caller passes the file as it is.
public enum RegistryEditor {
    /// What a new version of the project changes in the tap or bucket file.
    ///
    /// - Parameters:
    ///   - existing: the file with its blob SHA, or `nil` if it doesn't exist yet.
    ///   - description: the repository's description, for a new cask.
    public static func edit(
        _ setup: RegistrySetup,
        project: RepositorySlug,
        tag: String,
        asset: SelectedAsset,
        existing: GitHubFile?,
        description: String? = nil
    ) throws -> RegistryEdit {
        guard let repository = setup.repositorySlug, setup.writesFile else {
            throw DROPError(.invalidArgument, whatHappened: String(localized: "This registry isn't set up yet."))
        }
        let version = AssetPattern.version(fromTag: tag)
        let url = downloadURL(project: project, tag: tag, asset: asset.name)
        let sha256 = asset.sha256
        let token = ((setup.path as NSString).lastPathComponent as NSString).deletingPathExtension
        let newText: String
        let message: String
        switch (setup.destination, existing) {
        case (.homebrewTap, let file?):
            newText = try HomebrewFile.bump(file.text, version: version, sha256: sha256, url: url)
            message = "\(token) \(version)"
        case (.homebrewTap, nil):
            guard setup.path.hasPrefix("Casks/") else { throw missing(setup.path, in: repository) }
            newText = HomebrewFile.newCask(
                setup, project: project, version: version, sha256: sha256, url: url, description: description
            )
            message = "\(token) \(version) (new cask)"
        case (.scoopBucket, let file?):
            newText = try ScoopManifest.bump(file.text, version: version, url: url, hash: sha256)
            message = "\(token): Update to version \(version)"
        default:
            throw missing(setup.path, in: repository)
        }
        return RegistryEdit(
            destination: setup.destination,
            repository: repository,
            path: setup.path,
            oldText: existing?.text,
            blobSHA: existing?.sha,
            newText: newText,
            version: version,
            assetName: asset.name,
            sha256: sha256,
            message: message
        )
    }

    /// `https://github.com/{owner}/{repo}/releases/download/{tag}/{asset}`.
    public static func downloadURL(project: RepositorySlug, tag: String, asset: String) -> String {
        let allowed = CharacterSet.urlPathAllowed.subtracting(CharacterSet(charactersIn: "/"))
        let encodedTag = tag.addingPercentEncoding(withAllowedCharacters: allowed) ?? tag
        let encodedAsset = asset.addingPercentEncoding(withAllowedCharacters: allowed) ?? asset
        return "https://github.com/\(project)/releases/download/\(encodedTag)/\(encodedAsset)"
    }

    static func missing(_ path: String, in repository: RepositorySlug) -> DROPError {
        DROPError(
            .notFound,
            whatHappened: String(localized: "\(path) doesn't exist in \(repository.description)."),
            howToFix: String(localized: "Add it to the repository once; DROP keeps it up to date from then on.")
        )
    }
}
