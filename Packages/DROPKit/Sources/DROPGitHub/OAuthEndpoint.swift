import DROPCore
import Foundation

/// The code to show while signing in with device flow.
public struct DeviceAuthorization: Sendable, Equatable {
    /// Identifies this sign-in to GitHub. Never shown.
    public let deviceCode: String
    /// The code you type on GitHub, like `WDJB-MJHT`.
    public let userCode: String
    public let verificationURL: URL
    /// How long the code is valid, in seconds.
    public let expiresIn: TimeInterval
    /// How often to ask GitHub whether you approved, in seconds.
    public let interval: TimeInterval

    public init(
        deviceCode: String,
        userCode: String,
        verificationURL: URL,
        expiresIn: TimeInterval,
        interval: TimeInterval
    ) {
        self.deviceCode = deviceCode
        self.userCode = userCode
        self.verificationURL = verificationURL
        self.expiresIn = expiresIn
        self.interval = interval
    }
}

/// Tokens as GitHub hands them out. Expiry times are relative to the response.
public struct OAuthToken: Sendable, Equatable, CustomStringConvertible {
    public let accessToken: String
    /// `nil` when the token doesn't expire.
    public let accessTokenExpiresIn: TimeInterval?
    public let refreshToken: String?
    public let refreshTokenExpiresIn: TimeInterval?
    public let scopes: [String]

    public init(
        accessToken: String,
        accessTokenExpiresIn: TimeInterval? = nil,
        refreshToken: String? = nil,
        refreshTokenExpiresIn: TimeInterval? = nil,
        scopes: [String] = []
    ) {
        self.accessToken = accessToken
        self.accessTokenExpiresIn = accessTokenExpiresIn
        self.refreshToken = refreshToken
        self.refreshTokenExpiresIn = refreshTokenExpiresIn
        self.scopes = scopes
    }

    /// Never prints the tokens themselves.
    public var description: String { "OAuthToken(scopes: \(scopes), expires: \(accessTokenExpiresIn != nil))" }
}

/// The answer to one poll while waiting for you to approve the sign-in.
public enum DevicePollResult: Sendable, Equatable {
    case pending
    /// GitHub asks to poll less often, optionally naming the new interval.
    case slowDown(interval: TimeInterval?)
    case authorized(OAuthToken)
}

/// GitHub's OAuth endpoints for device flow and token refresh.
public protocol OAuthEndpoint: Sendable {
    func requestDeviceCode(scopes: [String]) async throws -> DeviceAuthorization
    func pollForToken(deviceCode: String) async throws -> DevicePollResult
    /// Exchanges a refresh token (single use) for new tokens. Throws `sessionExpired` when GitHub
    /// no longer accepts the refresh token.
    func refresh(refreshToken: String) async throws -> OAuthToken
}

/// `OAuthEndpoint` on github.com. Uses only the public Client ID; there is no client secret.
public struct GitHubOAuthEndpoint: OAuthEndpoint {
    static let deviceCodeURL = URL(string: "https://github.com/login/device/code")
    static let tokenURL = URL(string: "https://github.com/login/oauth/access_token")

    let clientID: String
    let transport: any HTTPTransport
    let userAgent: String

    public init(clientID: String, transport: any HTTPTransport, userAgent: String) {
        self.clientID = clientID
        self.transport = transport
        self.userAgent = userAgent
    }

    public func requestDeviceCode(scopes: [String]) async throws -> DeviceAuthorization {
        let body = try await post(Self.deviceCodeURL, form: [
            "client_id": clientID,
            "scope": scopes.joined(separator: " "),
        ])
        guard let deviceCode = body.string("device_code"), let userCode = body.string("user_code"),
            let verification = body.string("verification_uri").flatMap(URL.init(string:)),
            verification.scheme == "https"
        else { throw Self.failure(body) }
        return DeviceAuthorization(
            deviceCode: deviceCode,
            userCode: userCode,
            verificationURL: verification,
            expiresIn: body.number("expires_in") ?? 900,
            interval: body.number("interval") ?? 5
        )
    }

    public func pollForToken(deviceCode: String) async throws -> DevicePollResult {
        let body = try await post(Self.tokenURL, form: [
            "client_id": clientID,
            "device_code": deviceCode,
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ])
        switch body.string("error") {
        case nil: return .authorized(try Self.token(from: body))
        case "authorization_pending": return .pending
        case "slow_down": return .slowDown(interval: body.number("interval"))
        default: throw Self.failure(body)
        }
    }

    public func refresh(refreshToken: String) async throws -> OAuthToken {
        let body = try await post(Self.tokenURL, form: [
            "client_id": clientID,
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
        ])
        switch body.string("error") {
        case nil: return try Self.token(from: body)
        case "bad_refresh_token", "unauthorized_client", "incorrect_client_credentials": throw DROPError.sessionExpired
        default: throw Self.failure(body)
        }
    }

    private func post(_ url: URL?, form: [String: String]) async throws -> OAuthBody {
        guard let url else { throw DROPError.network(details: "Invalid OAuth URL") }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Accept")
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        request.httpBody = Data(FormEncoding.encode(form).utf8)
        let (data, response) = try await transport.send(request)
        guard let body = OAuthBody(data: data) else {
            throw DROPError.network(details: "HTTP \(response.statusCode) from GitHub sign-in")
        }
        return body
    }

    static func token(from body: OAuthBody) throws -> OAuthToken {
        guard let accessToken = body.string("access_token"), !accessToken.isEmpty else { throw failure(body) }
        let scopes = (body.string("scope") ?? "").split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        return OAuthToken(
            accessToken: accessToken,
            accessTokenExpiresIn: body.number("expires_in"),
            refreshToken: body.string("refresh_token"),
            refreshTokenExpiresIn: body.number("refresh_token_expires_in"),
            scopes: scopes.filter { !$0.isEmpty }
        )
    }

    static func failure(_ body: OAuthBody) -> DROPError {
        let code = body.string("error")
        let details = [code, body.string("error_description")].compactMap { $0 }.joined(separator: ": ")
        let whatHappened: String
        switch code {
        case "expired_token":
            return .signInCodeExpired
        case "access_denied":
            whatHappened = String(localized: "Signing in was cancelled on GitHub.")
        case "device_flow_disabled":
            whatHappened = String(localized: "Device flow is turned off for DROP's OAuth App on GitHub.")
        case "incorrect_client_credentials":
            whatHappened = String(localized: "GitHub doesn't know this build's Client ID.")
        default:
            whatHappened = String(localized: "Signing in with GitHub didn't work.")
        }
        return DROPError(
            .authorizationFailed,
            whatHappened: whatHappened,
            howToFix: String(localized: "Try signing in again."),
            details: details.isEmpty ? nil : details
        )
    }
}

extension DROPError {
    /// The device flow code ran out before it was approved on GitHub.
    public static var signInCodeExpired: DROPError {
        DROPError(
            .authorizationFailed,
            whatHappened: String(localized: "The sign-in code expired before it was approved."),
            howToFix: String(localized: "Try signing in again.")
        )
    }
}

/// The JSON object GitHub's OAuth endpoints answer with.
struct OAuthBody: Sendable {
    let values: [String: Value]

    enum Value: Sendable {
        case string(String)
        case number(Double)
    }

    init?(data: Data) {
        guard let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return nil }
        var values: [String: Value] = [:]
        for (key, value) in object {
            if let string = value as? String {
                values[key] = .string(string)
            } else if let number = value as? NSNumber {
                values[key] = .number(number.doubleValue)
            }
        }
        self.values = values
    }

    func string(_ key: String) -> String? {
        if case .string(let value) = values[key] { return value }
        return nil
    }

    func number(_ key: String) -> Double? {
        switch values[key] {
        case .number(let value): value
        case .string(let value): Double(value)
        case nil: nil
        }
    }
}

/// `application/x-www-form-urlencoded`, with keys sorted so the body is predictable.
enum FormEncoding {
    // RFC 3986 unreserved characters; everything else is percent-encoded.
    private static let allowed = CharacterSet(
        charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"
    )

    static func encode(_ form: [String: String]) -> String {
        form.sorted { $0.key < $1.key }
            .map { "\(escape($0.key))=\(escape($0.value))" }
            .joined(separator: "&")
    }

    private static func escape(_ text: String) -> String {
        text.addingPercentEncoding(withAllowedCharacters: allowed) ?? text
    }
}
