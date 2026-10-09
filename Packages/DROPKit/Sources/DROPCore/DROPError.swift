import Foundation

/// The single error type surfaced to the UI.
///
/// Every error carries a human-readable explanation of *what happened* and, where possible,
/// *how to fix it*. Messages must never contain tokens or other secrets.
public struct DROPError: Error, Sendable, Equatable {
    public enum Code: String, Sendable {
        case invalidArgument
        case storage
        case keychain
        /// A local file could not be read or written.
        case fileSystem
        /// A project or other item with the same name already exists.
        case alreadyExists
        /// GitHub or a registry could not be reached (offline, DNS, TLS, timeout).
        case network
        /// GitHub or a registry rejected a request (bad token, missing scope, rate limit).
        case rejected
        /// The repository or other item doesn't exist, or the account can't see it.
        case notFound
        /// GitHub's API rate limit is used up.
        case rateLimited
        /// No GitHub account is signed in.
        case signedOut
        /// The GitHub session ended (the refresh token expired or was revoked); sign in again.
        case sessionExpired
        /// Signing in didn't finish (denied, timed out, or device flow is off for the app).
        case authorizationFailed
        /// This build has no GitHub OAuth Client ID.
        case notConfigured
        /// Anything else.
        case unexpected
    }

    public let code: Code
    public let whatHappened: String
    public let howToFix: String?
    /// Extra technical detail. Shown behind a disclosure, never logged.
    public let details: String?

    public init(_ code: Code, whatHappened: String, howToFix: String? = nil, details: String? = nil) {
        self.code = code
        self.whatHappened = whatHappened
        self.howToFix = howToFix
        self.details = details
    }
}

extension DROPError: LocalizedError {
    public var errorDescription: String? { whatHappened }
    public var recoverySuggestion: String? { howToFix }
    public var failureReason: String? { details }
}

extension DROPError {
    /// `error` itself if it is a `DROPError`, otherwise a generic error that keeps its description.
    public static func wrapping(_ error: any Error) -> DROPError {
        if let error = error as? DROPError { return error }
        return DROPError(
            .unexpected,
            whatHappened: String(localized: "Something went wrong."),
            details: String(describing: error)
        )
    }

    /// The metadata store could not be opened, so DROP runs with a temporary one.
    public static func storageUnavailable(details: String) -> DROPError {
        DROPError(
            .storage,
            whatHappened: String(localized: "DROP could not open its project list."),
            howToFix: String(localized: """
                DROP is using a temporary list for now, so projects you add are not kept. \
                Quit and reopen DROP to try again.
                """),
            details: details
        )
    }

    public static func projectAlreadyAdded(_ slug: RepositorySlug) -> DROPError {
        DROPError(
            .alreadyExists,
            whatHappened: String(localized: "\(slug.description) is already in your projects.")
        )
    }

    public static var signedOut: DROPError {
        DROPError(
            .signedOut,
            whatHappened: String(localized: "You're not signed in to GitHub."),
            howToFix: String(localized: "Sign in with GitHub in Settings → Account.")
        )
    }

    public static var sessionExpired: DROPError {
        DROPError(
            .sessionExpired,
            whatHappened: String(localized: "Your GitHub session has ended."),
            howToFix: String(localized: "Sign in again to keep using DROP with GitHub.")
        )
    }

    public static var clientIDMissing: DROPError {
        DROPError(
            .notConfigured,
            whatHappened: String(localized: "This build of DROP has no GitHub Client ID."),
            howToFix: String(localized: "Set DROP_OAUTH_CLIENT_ID in Config/Local.xcconfig as described in SETUP.md.")
        )
    }

    public static func network(details: String) -> DROPError {
        DROPError(
            .network,
            whatHappened: String(localized: "DROP could not reach GitHub."),
            howToFix: String(localized: "Check your internet connection and try again."),
            details: details
        )
    }
}
