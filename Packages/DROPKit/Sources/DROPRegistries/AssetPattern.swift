import DROPCore
import Foundation

/// Picks the release asset a registry file points at, like `SMP-{version}.dmg` or `*-windows.zip`.
public enum AssetPattern {
    /// The version a tag stands for in registry files: `v1.2.3` → `1.2.3`.
    public static func version(fromTag tag: String) -> String {
        if tag.hasPrefix("v"), let next = tag.dropFirst().first, next.isNumber {
            return String(tag.dropFirst())
        }
        return tag
    }

    /// Whether `name` matches `pattern` once `{version}` is replaced. `*` matches any run of
    /// characters and `?` any one character; everything else matches itself.
    public static func matches(_ name: String, pattern: String, version: String) -> Bool {
        let expanded = pattern.trimmingCharacters(in: .whitespaces)
            .replacingOccurrences(of: "{version}", with: version)
        return glob(Array(expanded), Array(name))
    }

    /// The one asset in `names` that matches. Throws when none or several do, so a registry never
    /// points at a file you didn't mean.
    public static func select(from names: [String], pattern: String, version: String) throws -> String {
        let matching = names.filter { matches($0, pattern: pattern, version: version) }
        guard let first = matching.first else {
            throw DROPError(
                .notFound,
                whatHappened: String(localized: "No asset matches “\(pattern)”."),
                howToFix: String(localized: "Check the asset pattern, or attach the file to the drop.")
            )
        }
        guard matching.count == 1 else {
            throw DROPError(
                .invalidArgument,
                whatHappened: String(localized: "More than one asset matches “\(pattern)”."),
                howToFix: String(localized: "Make the asset pattern more specific, like “App-{version}.dmg”."),
                details: matching.joined(separator: ", ")
            )
        }
        return first
    }

    private static func glob(_ pattern: [Character], _ text: [Character]) -> Bool {
        // matched[index]: whether the pattern so far matches the first `index` characters of the text.
        var matched = [true] + Array(repeating: false, count: text.count)
        for character in pattern {
            var next = Array(repeating: false, count: text.count + 1)
            next[0] = character == "*" && matched[0]
            for index in stride(from: 1, through: text.count, by: 1) {
                if character == "*" {
                    next[index] = matched[index] || next[index - 1]
                } else {
                    next[index] = matched[index - 1] && (character == "?" || character == text[index - 1])
                }
            }
            matched = next
        }
        return matched[text.count]
    }
}
