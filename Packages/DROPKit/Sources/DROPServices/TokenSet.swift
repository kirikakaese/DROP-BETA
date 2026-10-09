import DROPGitHub
import Foundation

/// The tokens of the signed-in account with absolute expiry dates, as kept in the Keychain.
struct TokenSet: Codable, Sendable, Equatable {
    var accessToken: String
    /// `nil` when the access token doesn't expire.
    var accessTokenExpiresAt: Date?
    var refreshToken: String?
    var refreshTokenExpiresAt: Date?
    var scopes: [String]

    init(_ token: OAuthToken, issuedAt: Date) {
        accessToken = token.accessToken
        accessTokenExpiresAt = token.accessTokenExpiresIn.map { issuedAt.addingTimeInterval($0) }
        refreshToken = token.refreshToken
        refreshTokenExpiresAt = token.refreshTokenExpiresIn.map { issuedAt.addingTimeInterval($0) }
        scopes = token.scopes
    }

    /// Whether the access token expires within `leeway` seconds of `now` (or already has).
    func accessTokenExpires(within leeway: TimeInterval, of now: Date) -> Bool {
        guard let accessTokenExpiresAt else { return false }
        return accessTokenExpiresAt.timeIntervalSince(now) <= leeway
    }

    func isRefreshTokenUsable(at now: Date) -> Bool {
        guard refreshToken != nil else { return false }
        guard let refreshTokenExpiresAt else { return true }
        return refreshTokenExpiresAt > now
    }
}
