import Foundation

/// DROP's own repository on GitHub.
///
/// The slug is set once, in `Config/Repo.xcconfig`, and reaches the app through the
/// `DROPRepositorySlug` key in Info.plist. Nothing in the code spells it out, so renaming the
/// repository needs no code change.
public enum AppRepository {
    public static let infoPlistKey = "DROPRepositorySlug"

    /// The slug from the bundle's Info.plist, or `nil` outside the app (tests, previews).
    public static func slug(in bundle: Bundle = .main) -> RepositorySlug? {
        guard let value = bundle.object(forInfoDictionaryKey: infoPlistKey) as? String else { return nil }
        return RepositorySlug(parsing: value)
    }
}
