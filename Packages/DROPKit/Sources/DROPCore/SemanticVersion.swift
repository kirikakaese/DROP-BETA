import Foundation

/// A version following Semantic Versioning 2.0.0, like `1.2.3`, `2.0.0-beta.1` or `1.0.0+build.7`.
/// A leading `v` is accepted and dropped, so tag names parse directly.
public struct SemanticVersion: Hashable, Sendable, Comparable, CustomStringConvertible {
    public var major: Int
    public var minor: Int
    public var patch: Int
    /// Dot-separated prerelease identifiers, like `["beta", "1"]`. Empty for a release.
    public var prerelease: [String]
    /// Build metadata. Ignored when comparing.
    public var build: String?

    public init(major: Int, minor: Int, patch: Int, prerelease: [String] = [], build: String? = nil) {
        self.major = major
        self.minor = minor
        self.patch = patch
        self.prerelease = prerelease
        self.build = build
    }

    public init?(_ text: String) {
        var rest = Substring(text.trimmingCharacters(in: .whitespaces))
        if rest.first == "v" || rest.first == "V" { rest = rest.dropFirst() }
        var build: String?
        if let plus = rest.firstIndex(of: "+") {
            build = String(rest[rest.index(after: plus)...])
            rest = rest[..<plus]
            guard let build, Self.areValidIdentifiers(build.split(separator: ".", omittingEmptySubsequences: false))
            else { return nil }
        }
        var prerelease: [String] = []
        if let dash = rest.firstIndex(of: "-") {
            let identifiers = rest[rest.index(after: dash)...].split(separator: ".", omittingEmptySubsequences: false)
            guard Self.areValidIdentifiers(identifiers) else { return nil }
            prerelease = identifiers.map(String.init)
            rest = rest[..<dash]
        }
        let numbers = rest.split(separator: ".", omittingEmptySubsequences: false)
        guard numbers.count == 3 else { return nil }
        var values: [Int] = []
        for number in numbers {
            guard let value = Int(number), value >= 0, number.allSatisfy(\.isASCII),
                number == "0" || !number.hasPrefix("0")
            else { return nil }
            values.append(value)
        }
        self.init(major: values[0], minor: values[1], patch: values[2], prerelease: prerelease, build: build)
    }

    public var isPrerelease: Bool { !prerelease.isEmpty }

    /// The version without prerelease and build, like `1.2.3` for `1.2.3-beta.1`.
    public var core: SemanticVersion { SemanticVersion(major: major, minor: minor, patch: patch) }

    /// N for a `-beta.N` prerelease.
    public var betaNumber: Int? {
        guard prerelease.count == 2, prerelease[0] == "beta" else { return nil }
        return Int(prerelease[1])
    }

    public var description: String {
        var text = "\(major).\(minor).\(patch)"
        if isPrerelease { text += "-" + prerelease.joined(separator: ".") }
        if let build { text += "+" + build }
        return text
    }

    /// The next release for `bump`. Prerelease and build are dropped.
    public func bumped(_ bump: VersionBump) -> SemanticVersion {
        switch bump {
        case .major: SemanticVersion(major: major + 1, minor: 0, patch: 0)
        case .minor: SemanticVersion(major: major, minor: minor + 1, patch: 0)
        case .patch: SemanticVersion(major: major, minor: minor, patch: patch + 1)
        }
    }

    /// `self` as `-beta.N`.
    public func beta(_ number: Int) -> SemanticVersion {
        SemanticVersion(major: major, minor: minor, patch: patch, prerelease: ["beta", String(number)])
    }

    // Precedence as in semver.org §11: build metadata doesn't count, a prerelease comes before its
    // release, numeric identifiers compare as numbers and sort before alphanumeric ones.
    public static func < (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        if (lhs.major, lhs.minor, lhs.patch) != (rhs.major, rhs.minor, rhs.patch) {
            return (lhs.major, lhs.minor, lhs.patch) < (rhs.major, rhs.minor, rhs.patch)
        }
        switch (lhs.prerelease.isEmpty, rhs.prerelease.isEmpty) {
        case (true, true), (true, false): return false
        case (false, true): return true
        case (false, false): break
        }
        for (left, right) in zip(lhs.prerelease, rhs.prerelease) where left != right {
            switch (Int(left), Int(right)) {
            case let (left?, right?): return left < right
            case (.some, nil): return true
            case (nil, .some): return false
            case (nil, nil): return left < right
            }
        }
        return lhs.prerelease.count < rhs.prerelease.count
    }

    public static func == (lhs: SemanticVersion, rhs: SemanticVersion) -> Bool {
        lhs.major == rhs.major && lhs.minor == rhs.minor && lhs.patch == rhs.patch && lhs.prerelease == rhs.prerelease
    }

    public func hash(into hasher: inout Hasher) {
        hasher.combine(major)
        hasher.combine(minor)
        hasher.combine(patch)
        hasher.combine(prerelease)
    }

    private static func areValidIdentifiers(_ identifiers: [Substring]) -> Bool {
        identifiers.allSatisfy { identifier in
            !identifier.isEmpty
                && identifier.allSatisfy { $0.isASCII && ($0.isLetter || $0.isNumber || $0 == "-") }
        }
    }
}

/// Which part of the version a drop increases.
public enum VersionBump: String, CaseIterable, Sendable, Comparable {
    case patch
    case minor
    case major

    public var title: String {
        switch self {
        case .major: String(localized: "Major")
        case .minor: String(localized: "Minor")
        case .patch: String(localized: "Patch")
        }
    }

    public static func < (lhs: VersionBump, rhs: VersionBump) -> Bool {
        allCases.firstIndex(of: lhs) ?? 0 < allCases.firstIndex(of: rhs) ?? 0
    }
}
