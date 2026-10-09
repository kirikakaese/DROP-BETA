import Foundation

/// A commit, read as a Conventional Commit (`type(scope)!: summary`) when it is one. Squash-merged
/// pull requests end in ` (#123)`, which becomes `pullRequest`.
public struct ConventionalCommit: Hashable, Sendable {
    public let sha: String
    /// `feat`, `fix`, … in lowercase; `nil` when the subject doesn't follow Conventional Commits.
    public let type: String?
    public let scope: String?
    public let isBreaking: Bool
    /// The subject without type, scope and pull request number.
    public let summary: String
    public let pullRequest: Int?

    public init(
        sha: String,
        type: String?,
        scope: String?,
        isBreaking: Bool,
        summary: String,
        pullRequest: Int?
    ) {
        self.sha = sha
        self.type = type
        self.scope = scope
        self.isBreaking = isBreaking
        self.summary = summary
        self.pullRequest = pullRequest
    }

    /// Reads a full commit message: the subject line, then a body that may contain
    /// `BREAKING CHANGE:` (or `BREAKING-CHANGE:`).
    public init(sha: String, message: String) {
        let lines = message.split(separator: "\n", omittingEmptySubsequences: false)
        var subject = String(lines.first ?? "").trimmingCharacters(in: .whitespaces)
        var pullRequest: Int?
        if let match = Self.trailingPullRequest(in: subject) {
            pullRequest = match.number
            subject = match.rest
        }
        let footerBreaks = lines.dropFirst().contains { line in
            line.hasPrefix("BREAKING CHANGE:") || line.hasPrefix("BREAKING-CHANGE:")
        }
        if let header = Self.header(subject) {
            self.init(
                sha: sha,
                type: header.type,
                scope: header.scope,
                isBreaking: header.isBreaking || footerBreaks,
                summary: header.summary,
                pullRequest: pullRequest
            )
        } else {
            self.init(
                sha: sha, type: nil, scope: nil, isBreaking: footerBreaks, summary: subject, pullRequest: pullRequest
            )
        }
    }

    /// Merge commits carry no change of their own.
    public var isMerge: Bool {
        type == nil && (summary.hasPrefix("Merge pull request ") || summary.hasPrefix("Merge branch "))
    }

    /// The bump this commit asks for: breaking → major, `feat` → minor, anything else → patch.
    public var bump: VersionBump {
        if isBreaking { return .major }
        return type == "feat" ? .minor : .patch
    }

    private struct Header {
        let type: String
        let scope: String?
        let isBreaking: Bool
        let summary: String
    }

    private static func header(_ subject: String) -> Header? {
        guard let colon = subject.range(of: ": ") else { return nil }
        var prefix = subject[..<colon.lowerBound]
        let summary = subject[colon.upperBound...].trimmingCharacters(in: .whitespaces)
        guard !summary.isEmpty else { return nil }
        var isBreaking = false
        if prefix.hasSuffix("!") {
            isBreaking = true
            prefix = prefix.dropLast()
        }
        var scope: String?
        if prefix.hasSuffix(")"), let open = prefix.firstIndex(of: "(") {
            scope = String(prefix[prefix.index(after: open)..<prefix.index(before: prefix.endIndex)])
            prefix = prefix[..<open]
            guard let scope, !scope.isEmpty, !scope.contains("("), !scope.contains(")") else { return nil }
        }
        guard !prefix.isEmpty, prefix.allSatisfy({ $0.isASCII && $0.isLetter }) else { return nil }
        return Header(type: prefix.lowercased(), scope: scope, isBreaking: isBreaking, summary: summary)
    }

    private static func trailingPullRequest(in subject: String) -> (number: Int, rest: String)? {
        guard subject.hasSuffix(")"), let open = subject.range(of: " (#", options: .backwards) else { return nil }
        let digits = subject[open.upperBound..<subject.index(before: subject.endIndex)]
        guard let number = Int(digits), number > 0 else { return nil }
        return (number, String(subject[..<open.lowerBound]))
    }
}

/// What DROP suggests for the next drop, from the tags and the commits since the last release.
public struct VersionSuggestion: Hashable, Sendable {
    /// The newest release tag that isn't a prerelease, if there is one.
    public let latestRelease: String?
    /// The bump the commits ask for.
    public let bump: VersionBump
    /// `v` when existing tags use it (or there are none yet), otherwise empty.
    public let tagPrefix: String
    private let base: SemanticVersion?
    private let existing: Set<SemanticVersion>

    public init(tags: [String], commits: [ConventionalCommit]) {
        let versions = tags.compactMap { tag in SemanticVersion(tag).map { (tag, $0) } }
        let latest = versions.filter { !$0.1.isPrerelease }.max { $0.1 < $1.1 }
        latestRelease = latest?.0
        base = latest?.1
        existing = Set(versions.map(\.1))
        let usesV = versions.isEmpty || versions.contains { $0.0.hasPrefix("v") }
        tagPrefix = usesV ? "v" : ""
        var bump = commits.filter { !$0.isMerge }.map(\.bump).max() ?? .patch
        // Before 1.0, breaking changes bump the minor version.
        if bump == .major, let base = latest?.1, base.major == 0 { bump = .minor }
        self.bump = bump
    }

    /// The next release for `bump`: `0.1.0` when nothing was released yet.
    public func version(for bump: VersionBump) -> SemanticVersion {
        base?.bumped(bump) ?? SemanticVersion(major: 0, minor: 1, patch: 0)
    }

    /// The next `-beta.N` of that release, after any betas that are tagged already.
    public func betaVersion(for bump: VersionBump) -> SemanticVersion {
        let target = version(for: bump)
        let taken = existing.filter { $0.core == target }.compactMap(\.betaNumber).max() ?? 0
        return target.beta(taken + 1)
    }

    public func tagName(for bump: VersionBump, beta: Bool) -> String {
        tagPrefix + (beta ? betaVersion(for: bump) : version(for: bump)).description
    }
}
