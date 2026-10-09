import Foundation

/// The GitHub OAuth App DROP signs in with.
///
/// The Client ID is public: it identifies the app, not the user. It comes from
/// `DROP_OAUTH_CLIENT_ID` (Config/Local.xcconfig locally, the `DROP_OAUTH_CLIENT_ID` repository
/// variable in CI) and reaches the app through the `DROPOAuthClientID` key in Info.plist. The app
/// has no client secret; device flow doesn't need one.
public enum OAuthConfiguration {
    public static let infoPlistKey = "DROPOAuthClientID"

    /// The scopes DROP asks for when you sign in. `repo` covers tags, GitHub Releases, assets and
    /// pull requests in public and private repositories.
    public static let signInScopes = ["repo"]

    /// The Client ID from the bundle's Info.plist, or `nil` if the build has none.
    public static func clientID(in bundle: Bundle = .main) -> String? {
        guard let value = bundle.object(forInfoDictionaryKey: infoPlistKey) as? String else { return nil }
        let trimmed = value.trimmingCharacters(in: .whitespaces)
        return trimmed.isEmpty ? nil : trimmed
    }
}
