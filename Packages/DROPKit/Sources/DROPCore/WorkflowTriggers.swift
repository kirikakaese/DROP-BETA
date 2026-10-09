import Foundation

/// How a workflow starts, read from its YAML `on:` section. Only what DROP needs: whether it can be
/// run by hand, and whether pushing a tag starts it.
public struct WorkflowTriggers: Hashable, Sendable {
    public var dispatch = false
    /// `push` with `tags:` (any pattern).
    public var tagPush = false
    /// The tag patterns, like `v*`; empty when the workflow starts on any tag.
    public var tagPatterns: [String] = []
    /// `release: types: [published]` and the like.
    public var release = false

    public init(dispatch: Bool = false, tagPush: Bool = false, tagPatterns: [String] = [], release: Bool = false) {
        self.dispatch = dispatch
        self.tagPush = tagPush
        self.tagPatterns = tagPatterns
        self.release = release
    }

    /// Reads the triggers. Handles the common forms: `on: push`, `on: [push, workflow_dispatch]`
    /// and the block form with `push: tags:` lists. It doesn't evaluate anything else in the file.
    public init(yaml: String) {
        self.init()
        let lines = yaml.components(separatedBy: .newlines).map(Self.withoutComment)
        guard let onIndex = lines.firstIndex(where: { Self.isOnKey($0) }) else { return }
        let onLine = lines[onIndex]
        let inline = onLine.split(separator: ":", maxSplits: 1).dropFirst().first?
            .trimmingCharacters(in: .whitespaces) ?? ""
        if !inline.isEmpty {
            let names = inline.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
                .split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            dispatch = names.contains("workflow_dispatch")
            release = names.contains("release")
            // `on: push` without filters also runs for tags.
            tagPush = names.contains("push")
            return
        }
        readBlock(lines[(onIndex + 1)...], baseIndent: Self.indent(of: onLine))
    }

    /// Reads the block under `on:`: one key per event, with `push:` filters below it.
    private mutating func readBlock(_ lines: ArraySlice<String>, baseIndent: Int) {
        let content = lines.filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        guard let first = content.first, Self.indent(of: first) > baseIndent else { return }
        let eventIndent = Self.indent(of: first)
        var event = ""
        var hasPush = false
        var pushHasFilters = false
        var inTags = false
        for line in content {
            let indent = Self.indent(of: line)
            guard indent > baseIndent else { break }
            let text = line.trimmingCharacters(in: .whitespaces)
            if indent == eventIndent {
                event = String(text.split(separator: ":").first ?? "")
                inTags = false
                switch event {
                case "workflow_dispatch": dispatch = true
                case "release": release = true
                case "push": hasPush = true
                default: break
                }
                continue
            }
            guard event == "push" else { continue }
            if text.hasPrefix("tags:") {
                tagPush = true
                pushHasFilters = true
                inTags = true
                let rest = text.dropFirst("tags:".count).trimmingCharacters(in: .whitespaces)
                if !rest.isEmpty { tagPatterns += Self.listItems(rest) }
            } else if inTags, text.hasPrefix("- ") {
                tagPatterns.append(Self.unquoted(String(text.dropFirst(2))))
            } else if text.hasPrefix("branches") || text.hasPrefix("paths") {
                pushHasFilters = true
                inTags = false
            } else if !text.hasPrefix("- ") {
                inTags = false
            }
        }
        // `push:` without any filter runs for every branch and every tag.
        if hasPush && !pushHasFilters { tagPush = true }
    }

    /// Whether pushing `tag` starts the workflow, matching `tags:` patterns with `*` and `**`.
    public func startsOnPush(of tag: String) -> Bool {
        guard tagPush else { return false }
        guard !tagPatterns.isEmpty else { return true }
        return tagPatterns.contains { Self.glob($0, matches: tag) }
    }

    // MARK: Helpers

    private static func isOnKey(_ line: String) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        guard indent(of: line) == 0 else { return false }
        return ["on:", "\"on\":", "'on':"].contains { trimmed == $0 || trimmed.hasPrefix($0 + " ") }
    }

    private static func withoutComment(_ line: String) -> String {
        if line.trimmingCharacters(in: .whitespaces).hasPrefix("#") { return "" }
        guard let hash = line.range(of: " #") else { return line }
        return String(line[..<hash.lowerBound])
    }

    private static func indent(of line: String) -> Int {
        line.prefix { $0 == " " }.count
    }

    private static func listItems(_ text: String) -> [String] {
        text.trimmingCharacters(in: CharacterSet(charactersIn: "[]"))
            .split(separator: ",")
            .map { unquoted($0.trimmingCharacters(in: .whitespaces)) }
            .filter { !$0.isEmpty }
    }

    private static func unquoted(_ text: String) -> String {
        text.trimmingCharacters(in: CharacterSet(charactersIn: "\"' "))
    }

    /// GitHub's filter patterns: `*` matches anything but `/`, `**` matches anything.
    static func glob(_ pattern: String, matches text: String) -> Bool {
        var regex = "^"
        var index = pattern.startIndex
        while index < pattern.endIndex {
            let character = pattern[index]
            if character == "*" {
                let next = pattern.index(after: index)
                if next < pattern.endIndex, pattern[next] == "*" {
                    regex += ".*"
                    index = pattern.index(after: next)
                    continue
                }
                regex += "[^/]*"
            } else {
                regex += NSRegularExpression.escapedPattern(for: String(character))
            }
            index = pattern.index(after: index)
        }
        regex += "$"
        return text.range(of: regex, options: .regularExpression) != nil
    }
}
