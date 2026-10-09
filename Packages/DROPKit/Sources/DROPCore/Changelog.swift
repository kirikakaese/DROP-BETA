import Foundation

/// Release notes from Conventional Commits, grouped by type, with links to pull requests and the
/// compare view. The notes are written in English, like the commits they come from.
public enum Changelog {
    /// Types whose commits are left out of the notes: they don't change what people use.
    public static let hiddenTypes: Set<String> = ["chore", "ci", "test", "style", "build"]

    static let groups: [(title: String, types: Set<String>)] = [
        ("Features", ["feat"]),
        ("Fixes", ["fix"]),
        ("Performance", ["perf"]),
        ("Other Changes", ["refactor", "docs", "revert"]),
    ]

    /// The notes for one drop. `headingLevel` is 2 for a GitHub Release and 3 inside CHANGELOG.md.
    public static func notes(
        for commits: [ConventionalCommit],
        slug: RepositorySlug,
        previousTag: String?,
        newTag: String,
        headingLevel: Int = 2
    ) -> String {
        let shown = commits.filter { !$0.isMerge && !hiddenTypes.contains($0.type ?? "") }
        let heading = String(repeating: "#", count: headingLevel)
        var sections: [String] = []

        let breaking = shown.filter(\.isBreaking)
        if !breaking.isEmpty {
            sections.append(section("\(heading) Breaking Changes", breaking, slug: slug))
        }
        for group in groups {
            let matching = shown.filter { !$0.isBreaking && group.types.contains($0.type ?? "") }
            if !matching.isEmpty {
                sections.append(section("\(heading) \(group.title)", matching, slug: slug))
            }
        }
        let others = shown.filter { !$0.isBreaking && $0.type == nil }
        if !others.isEmpty {
            sections.append(section("\(heading) Other Changes", others, slug: slug))
        }
        if let previousTag {
            let compare = "https://github.com/\(slug)/compare/\(previousTag)...\(newTag)"
            sections.append("**Full Changelog**: [\(previousTag)...\(newTag)](\(compare))")
        }
        return sections.joined(separator: "\n\n") + "\n"
    }

    private static func section(_ title: String, _ commits: [ConventionalCommit], slug: RepositorySlug) -> String {
        ([title, ""] + commits.map { line(for: $0, slug: slug) }).joined(separator: "\n")
    }

    static func line(for commit: ConventionalCommit, slug: RepositorySlug) -> String {
        var text = "- "
        if let scope = commit.scope { text += "**\(scope):** " }
        text += commit.summary
        if let number = commit.pullRequest {
            text += " ([#\(number)](https://github.com/\(slug)/pull/\(number)))"
        } else if commit.sha.count >= 7 {
            let short = String(commit.sha.prefix(7))
            text += " ([\(short)](https://github.com/\(slug)/commit/\(commit.sha)))"
        }
        return text
    }

    /// `CHANGELOG.md` with a section for `version` added at the top, below the title. An existing
    /// section for the same version is replaced, so dropping again doesn't add it twice.
    public static func updatingFile(
        _ existing: String?,
        version: String,
        date: Date,
        notes: String
    ) -> String {
        let day = date.formatted(.iso8601.year().month().day())
        let section = "## \(version) - \(day)\n\n\(notes.trimmingCharacters(in: .whitespacesAndNewlines))\n"
        guard let existing, !existing.isEmpty else {
            return "# Changelog\n\n" + section
        }
        var lines = existing.components(separatedBy: "\n")
        if let start = lines.firstIndex(where: { isHeading($0, for: version) }) {
            let end = lines[(start + 1)...].firstIndex { $0.hasPrefix("## ") } ?? lines.endIndex
            lines.removeSubrange(start..<end)
        }
        let insertAt = lines.firstIndex { $0.hasPrefix("## ") } ?? lines.endIndex
        var block = section.components(separatedBy: "\n")
        if insertAt == lines.endIndex, lines.last?.isEmpty == false { block.insert("", at: 0) }
        lines.insert(contentsOf: block, at: insertAt)
        return lines.joined(separator: "\n")
    }

    /// Notes written for a GitHub Release (`## Features`) one heading level deeper, so they fit
    /// below a version heading in CHANGELOG.md (`### Features`).
    public static func demotingHeadings(_ notes: String) -> String {
        notes.components(separatedBy: "\n")
            .map { $0.hasPrefix("#") ? "#" + $0 : $0 }
            .joined(separator: "\n")
    }

    private static func isHeading(_ line: String, for version: String) -> Bool {
        guard line.hasPrefix("## ") else { return false }
        let rest = line.dropFirst(3).trimmingCharacters(in: .whitespaces)
        let bare = version.hasPrefix("v") ? String(version.dropFirst()) : version
        let names = [version, bare, "[\(version)]", "[\(bare)]"]
        return names.contains { rest == $0 || rest.hasPrefix($0 + " ") }
    }
}
