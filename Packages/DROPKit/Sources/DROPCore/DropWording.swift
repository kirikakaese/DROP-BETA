import Foundation

/// The words for DROP's main action, kept in one place so every button, menu, progress line and
/// notification says the same thing. "Drop" is what you do; a GitHub Release is what GitHub stores.
public enum DropWording {
    /// "Drop", or "Drop v1.2.3" once the version is known.
    public static func actionTitle(version: String?) -> String {
        guard let version, !version.isEmpty else { return String(localized: "Drop") }
        return String(localized: "Drop v\(trimmedVersion(version))")
    }

    /// The menu item, which opens the plan before anything happens.
    public static var menuTitle: String { String(localized: "Drop…") }

    /// The option that marks the GitHub Release as a prerelease.
    public static var betaTitle: String { String(localized: "Drop a Beta") }

    public static var readyTitle: String { String(localized: "Ready to Drop") }

    public static var historyTitle: String { String(localized: "Drops") }

    public static func progressTitle(version: String) -> String {
        String(localized: "Dropping v\(trimmedVersion(version))…")
    }

    public static func doneTitle(version: String) -> String {
        String(localized: "Dropped v\(trimmedVersion(version))")
    }

    public static var failedTitle: String { String(localized: "Drop failed") }

    /// Accepts "1.2.3" and "v1.2.3" alike, so a tag name can be passed as it is.
    static func trimmedVersion(_ version: String) -> String {
        version.hasPrefix("v") || version.hasPrefix("V") ? String(version.dropFirst()) : version
    }
}
