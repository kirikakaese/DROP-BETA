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
        /// A project or other item with the same name already exists.
        case alreadyExists
        /// GitHub or a registry could not be reached (offline, DNS, TLS, timeout).
        case network
        /// GitHub or a registry rejected a request (bad token, missing scope, rate limit).
        case rejected
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
}
