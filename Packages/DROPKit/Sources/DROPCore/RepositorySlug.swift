import Foundation

/// A GitHub repository as `owner/name`.
///
/// GitHub treats names case-insensitively, so two slugs are equal when they differ only in case.
/// `description` keeps the spelling GitHub returned.
public struct RepositorySlug: Hashable, Sendable, Codable, CustomStringConvertible {
    public let owner: String
    public let name: String

    /// Creates a slug from an owner and a name, or returns `nil` if either isn't valid on GitHub.
    public init?(owner: String, name: String) {
        guard Self.isValidOwner(owner), Self.isValidName(name) else { return nil }
        self.owner = owner
        self.name = name
    }

    /// Parses `owner/name`, `https://github.com/owner/name(.git)` or `git@github.com:owner/name.git`.
    public init?(parsing input: String) {
        var text = input.trimmingCharacters(in: .whitespacesAndNewlines)
        for prefix in ["https://github.com/", "http://github.com/", "github.com/", "git@github.com:"]
        where text.lowercased().hasPrefix(prefix) {
            text = String(text.dropFirst(prefix.count))
            break
        }
        if text.hasSuffix("/") { text.removeLast() }
        if text.lowercased().hasSuffix(".git") { text.removeLast(4) }
        let parts = text.split(separator: "/", omittingEmptySubsequences: false)
        guard parts.count == 2 else { return nil }
        self.init(owner: String(parts[0]), name: String(parts[1]))
    }

    public var description: String { "\(owner)/\(name)" }

    /// The repository's page on github.com.
    public var webURL: URL {
        // Owner and name are validated to URL-safe characters, so this always succeeds.
        URL(string: "https://github.com/\(owner)/\(name)") ?? URL(filePath: "/")
    }

    public static func == (lhs: RepositorySlug, rhs: RepositorySlug) -> Bool {
        lhs.owner.lowercased() == rhs.owner.lowercased() && lhs.name.lowercased() == rhs.name.lowercased()
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(owner.lowercased())
        hasher.combine(name.lowercased())
    }

    public init(from decoder: any Decoder) throws {
        let text = try decoder.singleValueContainer().decode(String.self)
        guard let slug = RepositorySlug(parsing: text) else {
            throw DecodingError.dataCorrupted(.init(
                codingPath: decoder.codingPath, debugDescription: "Not a repository slug"
            ))
        }
        self = slug
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(description)
    }

    // GitHub user and organization names: 1–39 letters, digits or single hyphens, not at either end.
    static func isValidOwner(_ owner: String) -> Bool {
        guard (1...39).contains(owner.count), !owner.hasPrefix("-"), !owner.hasSuffix("-"),
            !owner.contains("--")
        else { return false }
        return owner.unicodeScalars.allSatisfy { isASCIIAlphanumeric($0) || $0 == "-" }
    }

    // Repository names: 1–100 letters, digits, `.`, `-` or `_`, but not `.` or `..`.
    static func isValidName(_ name: String) -> Bool {
        guard (1...100).contains(name.count), name != ".", name != ".." else { return false }
        return name.unicodeScalars.allSatisfy { isASCIIAlphanumeric($0) || "._-".unicodeScalars.contains($0) }
    }

    private static func isASCIIAlphanumeric(_ scalar: Unicode.Scalar) -> Bool {
        scalar.isASCII && CharacterSet.alphanumerics.contains(scalar)
    }
}
