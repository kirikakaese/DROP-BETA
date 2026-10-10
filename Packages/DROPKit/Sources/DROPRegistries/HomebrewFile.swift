import DROPCore
import Foundation

/// Updates a Homebrew cask or formula for a new version, changing only its `version`, `sha256` and
/// `url` lines, and writes new casks.
public enum HomebrewFile {
    public enum Kind: Sendable {
        case cask
        case formula
    }

    /// Whether `text` is a cask or a formula, if it is either.
    public static func kind(of text: String) -> Kind? {
        for line in text.components(separatedBy: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("cask \"") { return .cask }
            if trimmed.hasPrefix("class "), trimmed.contains("< Formula") { return .formula }
        }
        return nil
    }

    /// The URL as written into a cask: the version replaced by `#{version}`, so the next update
    /// only needs to change `version` and `sha256`.
    public static func interpolated(url: String, version: String) -> String {
        url.replacingOccurrences(of: version, with: "#{version}")
    }

    /// `text` updated to `version`. A cask's URL keeps `#{version}` where it has it; a formula gets
    /// the plain URL, because Homebrew reads a formula's version from it.
    ///
    /// Only the top-level stanzas are changed (indented by two spaces), so `resource`, `livecheck`
    /// and `bottle` blocks are left alone. Files with one download per architecture are refused.
    public static func bump(_ text: String, version: String, sha256: String, url: String) throws -> String {
        guard let kind = kind(of: text) else {
            throw unsupported(String(localized: "It is neither a Homebrew cask nor a formula."))
        }
        var lines = text.components(separatedBy: "\n")
        var hasVersion = false
        var checksums = 0
        var urls = 0
        for index in lines.indices {
            let line = lines[index]
            guard line.hasPrefix("  "), !line.hasPrefix("   ") else { continue }
            let stanza = line.dropFirst(2)
            if stanza.hasPrefix("version ") {
                lines[index] = "  version \(quoted(version))"
                hasVersion = true
            } else if stanza.hasPrefix("sha256 ") {
                guard stanza.hasPrefix("sha256 \"") else {
                    throw unsupported(String(localized: "It has one download per architecture, or no checksum."))
                }
                lines[index] = "  sha256 \(quoted(sha256))"
                checksums += 1
            } else if stanza.hasPrefix("url ") {
                lines[index] = try updatedURL(line, kind: kind, version: version, url: url)
                urls += 1
            }
        }
        guard checksums == 1, urls == 1 else {
            throw unsupported(String(localized: "It has one download per architecture, or no checksum."))
        }
        if kind == .cask, !hasVersion {
            throw unsupported(String(localized: "The cask has no version."))
        }
        return lines.joined(separator: "\n")
    }

    /// A new cask for `project` that installs the setup's app from `url`.
    public static func newCask(
        _ setup: RegistrySetup,
        project: RepositorySlug,
        version: String,
        sha256: String,
        url: String,
        description: String?
    ) -> String {
        let token = ((setup.path as NSString).lastPathComponent as NSString).deletingPathExtension
        var app = setup.appName.trimmingCharacters(in: .whitespaces)
        if app.isEmpty { app = "\(project.name).app" }
        var lines = [
            "cask \(quoted(token)) do",
            "  version \(quoted(version))",
            "  sha256 \(quoted(sha256))",
            "",
            "  url \(quoted(interpolated(url: url, version: version)))",
            "  name \(quoted(project.name))",
        ]
        if let description = description?.trimmingCharacters(in: .whitespacesAndNewlines), !description.isEmpty {
            var sentence = description
            if sentence.hasSuffix(".") { sentence.removeLast() }
            lines.append("  desc \(quoted(sentence))")
        }
        lines += [
            "  homepage \(quoted("https://github.com/\(project)"))",
            "",
            "  app \(quoted(app))",
            "end",
            "",
        ]
        return lines.joined(separator: "\n")
    }

    /// Replaces the first string of a `url` line. A cask URL that already uses `#{version}` stays.
    private static func updatedURL(_ line: String, kind: Kind, version: String, url: String) throws -> String {
        guard let open = line.firstIndex(of: "\""),
            let close = line[line.index(after: open)...].firstIndex(of: "\"")
        else {
            throw unsupported(String(localized: "Its URL isn't a plain string."))
        }
        let current = line[line.index(after: open)..<close]
        var value = url
        if kind == .cask {
            if current.contains("#{version}") { return line }
            value = interpolated(url: url, version: version)
        }
        return String(line[..<open]) + quoted(value) + String(line[line.index(after: close)...])
    }

    /// A Ruby string literal.
    static func quoted(_ text: String) -> String {
        let escaped = text.replacingOccurrences(of: "\\", with: "\\\\").replacingOccurrences(of: "\"", with: "\\\"")
        return "\"\(escaped)\""
    }

    private static func unsupported(_ reason: String) -> DROPError {
        DROPError(
            .invalidArgument,
            whatHappened: String(localized: "DROP can't update this Homebrew file. \(reason)"),
            howToFix: String(localized: "Update it by hand, or let the automation that maintains it keep doing so.")
        )
    }
}
