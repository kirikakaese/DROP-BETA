import Foundation

/// Where a drop ends up: the GitHub Release itself and the package registries.
public enum Destination: String, CaseIterable, Identifiable, Sendable, Codable {
    case githubRelease
    case homebrewTap
    case scoopBucket
    case ghcr
    case npm

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .githubRelease: String(localized: "GitHub Release")
        case .homebrewTap: String(localized: "Homebrew Tap")
        case .scoopBucket: String(localized: "Scoop Bucket")
        case .ghcr: String(localized: "GitHub Container Registry")
        case .npm: String(localized: "npm")
        }
    }

    public var systemImage: String {
        switch self {
        case .githubRelease: "tag"
        case .homebrewTap: "mug"
        case .scoopBucket: "takeoutbag.and.cup.and.straw"
        case .ghcr: "shippingbox"
        case .npm: "cube"
        }
    }
}

/// Who performs a destination's step.
public enum OwnershipMode: String, CaseIterable, Sendable, Codable {
    /// DROP does it.
    case managed
    /// An existing automation does it; DROP only watches and verifies, and never writes.
    case external
    case off

    public var title: String {
        switch self {
        case .managed: String(localized: "Managed")
        case .external: String(localized: "External")
        case .off: String(localized: "Off")
        }
    }
}

/// The choice for one destination of one project.
public struct DestinationSetting: Hashable, Sendable, Identifiable {
    public var id: Destination { destination }
    public let destination: Destination
    public var mode: OwnershipMode
    /// The automation that owns it when external, like `.github/workflows/release.yml`.
    public var owner: String?

    public init(destination: Destination, mode: OwnershipMode, owner: String? = nil) {
        self.destination = destination
        self.mode = mode
        self.owner = owner
    }

    /// The owner's file name, like `release.yml`, for short labels.
    public var ownerName: String? {
        owner.map { ($0 as NSString).lastPathComponent }
    }
}

/// Existing automation that already performs a destination's step.
public struct AutomationFinding: Hashable, Sendable {
    public let destination: Destination
    /// The file that does it, like `.github/workflows/release.yml` or `.goreleaser.yaml`.
    public let owner: String
    /// What gave it away, like `uses: softprops/action-gh-release`.
    public let evidence: String

    public init(destination: Destination, owner: String, evidence: String) {
        self.destination = destination
        self.owner = owner
        self.evidence = evidence
    }
}

/// Finds release automation in workflow and tool configuration files. It reads text and never runs
/// anything. When automation is found, the destination defaults to External.
public enum AutomationDetector {
    struct Rule {
        let destination: Destination
        let needle: String
    }

    /// Text that marks a workflow step or tool doing the destination's job.
    static let workflowRules: [Rule] = [
        Rule(destination: .githubRelease, needle: "softprops/action-gh-release"),
        Rule(destination: .githubRelease, needle: "ncipollo/release-action"),
        Rule(destination: .githubRelease, needle: "actions/create-release"),
        Rule(destination: .githubRelease, needle: "gh release create"),
        Rule(destination: .githubRelease, needle: "goreleaser/goreleaser-action"),
        Rule(destination: .githubRelease, needle: "googleapis/release-please-action"),
        Rule(destination: .githubRelease, needle: "google-github-actions/release-please-action"),
        Rule(destination: .githubRelease, needle: "semantic-release"),
        Rule(destination: .homebrewTap, needle: "homebrew-tap"),
        Rule(destination: .homebrewTap, needle: "bump-homebrew-formula"),
        Rule(destination: .homebrewTap, needle: "brew bump-cask-pr"),
        Rule(destination: .homebrewTap, needle: "brew bump-formula-pr"),
        Rule(destination: .scoopBucket, needle: "scoop-bucket"),
        Rule(destination: .scoopBucket, needle: "scoop bucket"),
        Rule(destination: .ghcr, needle: "docker/build-push-action"),
        Rule(destination: .ghcr, needle: "docker push ghcr.io"),
        Rule(destination: .npm, needle: "npm publish"),
        Rule(destination: .npm, needle: "js-devtools/npm-publish"),
        Rule(destination: .npm, needle: "changesets/action"),
    ]

    /// What a GoReleaser configuration publishes, by its top-level keys.
    static let goreleaserKeys: [(key: String, destination: Destination)] = [
        ("release:", .githubRelease),
        ("brews:", .homebrewTap),
        ("homebrew_casks:", .homebrewTap),
        ("scoops:", .scoopBucket),
        ("dockers:", .ghcr),
        ("docker_manifests:", .ghcr),
        ("npms:", .npm),
    ]

    /// The configuration files besides workflows that DROP looks at.
    public static let configFiles = [
        ".goreleaser.yml", ".goreleaser.yaml", ".releaserc", ".releaserc.json", ".releaserc.yml",
        "release-please-config.json", ".changeset/config.json",
    ]

    /// Findings in `files` (path → text), one per destination and owner.
    public static func findings(in files: [String: String]) -> [AutomationFinding] {
        var findings: [AutomationFinding] = []
        for (path, text) in files.sorted(by: { $0.key < $1.key }) {
            let lowered = text.lowercased()
            func add(_ destination: Destination, _ evidence: String) {
                append(AutomationFinding(destination: destination, owner: path, evidence: evidence), to: &findings)
            }
            if path.hasPrefix(".github/workflows/") {
                for rule in workflowRules where lowered.contains(rule.needle) {
                    add(rule.destination, rule.needle)
                }
            } else if path.contains("goreleaser") {
                // GoReleaser always creates the GitHub Release unless `release: disable: true`.
                if !lowered.contains("disable: true") { add(.githubRelease, "goreleaser") }
                let lines = lowered.components(separatedBy: "\n")
                for entry in goreleaserKeys where lines.contains(where: { $0.hasPrefix(entry.key) }) {
                    if entry.destination != .githubRelease { add(entry.destination, entry.key) }
                }
            } else if path.contains("releaserc") || path.contains("release-please") || path.contains(".changeset") {
                add(.githubRelease, path)
            }
        }
        return findings
    }

    /// The setting for each destination: what's stored wins; otherwise External when automation was
    /// found, Managed for the GitHub Release and Off for registries.
    public static func settings(
        stored: [DestinationSetting],
        findings: [AutomationFinding]
    ) -> [DestinationSetting] {
        Destination.allCases.map { destination in
            if let saved = stored.first(where: { $0.destination == destination }) { return saved }
            if let found = findings.first(where: { $0.destination == destination }) {
                return DestinationSetting(destination: destination, mode: .external, owner: found.owner)
            }
            return DestinationSetting(destination: destination, mode: destination == .githubRelease ? .managed : .off)
        }
    }

    private static func append(_ finding: AutomationFinding, to findings: inout [AutomationFinding]) {
        guard !findings.contains(where: { $0.destination == finding.destination && $0.owner == finding.owner }) else {
            return
        }
        findings.append(finding)
    }
}
