import Foundation

/// The words for DROP's main action, kept in one place so every button, menu and message says the
/// same thing. "Drop" is what you do; a GitHub Release is what GitHub stores.
public enum DropWording {
    /// "Drop", or "Drop v1.2.3" once the version is known.
    public static func actionTitle(version: String?) -> String {
        guard let version, !version.isEmpty else { return String(localized: "Drop") }
        return String(localized: "Drop v\(trimmedVersion(version))")
    }

    /// The menu item, which opens the plan before anything happens.
    public static var menuTitle: String { String(localized: "Drop…") }

    /// Accepts "1.2.3" and "v1.2.3" alike, so a tag name can be passed as it is.
    static func trimmedVersion(_ version: String) -> String {
        version.hasPrefix("v") || version.hasPrefix("V") ? String(version.dropFirst()) : version
    }
}
