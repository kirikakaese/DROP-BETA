import DROPCore
import DROPGitHub
import Foundation

/// Whether an account is signed in.
public enum AuthState: Sendable, Equatable {
    case signedOut
    case signedIn
    /// The session ended on its own (refresh token expired or revoked); sign in again.
    case sessionExpired
}

/// Signing in with GitHub and handing out access tokens.
public protocol AuthServicing: AccessTokenProviding {
    /// Whether this build has a Client ID and can sign in at all.
    var canSignIn: Bool { get }
    func state() async -> AuthState
    /// Step 1 of device flow: get the code to show, asking for `scopes`.
    func startSignIn(scopes: [String]) async throws -> DeviceAuthorization
    /// Step 2: wait until the code was approved on GitHub, then keep the tokens. Cancellable.
    func finishSignIn(_ authorization: DeviceAuthorization) async throws
    func signOut() async throws
    /// The scopes GitHub granted, or empty when it didn't say (then only trying tells).
    func grantedScopes() async -> [String]
}

extension AuthServicing {
    public func startSignIn() async throws -> DeviceAuthorization {
        try await startSignIn(scopes: OAuthConfiguration.signInScopes)
    }
}

/// The token lifecycle: device flow, Keychain storage, refreshing before expiry and after a 401.
///
/// A refresh token can be used only once, so refreshing runs behind this actor: callers that need a
/// refresh while one is running wait for it and share its result instead of starting another one,
/// which would invalidate the first and sign you out.
public actor AuthService: AuthServicing {
    static let keychainAccount = "github"

    private let endpoint: (any OAuthEndpoint)?
    private let secrets: any SecretStoring
    private let now: @Sendable () -> Date
    private let sleep: @Sendable (Duration) async throws -> Void
    /// Tokens are refreshed when they expire within this many seconds.
    private let refreshLeeway: TimeInterval

    private var cached: TokenSet?
    private var isLoaded = false
    private var sessionEnded = false
    private var refreshTask: Task<TokenSet, any Error>?

    public nonisolated let canSignIn: Bool

    public init(
        endpoint: (any OAuthEndpoint)?,
        secrets: any SecretStoring,
        now: @escaping @Sendable () -> Date = { Date() },
        sleep: @escaping @Sendable (Duration) async throws -> Void = { try await Task.sleep(for: $0) },
        refreshLeeway: TimeInterval = 300
    ) {
        self.endpoint = endpoint
        self.secrets = secrets
        self.now = now
        self.sleep = sleep
        self.refreshLeeway = refreshLeeway
        canSignIn = endpoint != nil
    }

    // MARK: State

    public func state() async -> AuthState {
        guard let tokens = try? loadTokens() else { return sessionEnded ? .sessionExpired : .signedOut }
        if tokens.accessTokenExpires(within: 0, of: now()) && !tokens.isRefreshTokenUsable(at: now()) {
            return .sessionExpired
        }
        return .signedIn
    }

    // MARK: Tokens

    public func accessToken() async throws -> String {
        let tokens = try requireTokens()
        guard tokens.accessTokenExpires(within: refreshLeeway, of: now()) else { return tokens.accessToken }
        do {
            return try await refreshed(from: tokens).accessToken
        } catch let error as DROPError where error.code != .sessionExpired {
            // Refreshing early failed (offline?); the old token still works until it expires.
            if !tokens.accessTokenExpires(within: 0, of: now()) { return tokens.accessToken }
            throw error
        }
    }

    public func accessToken(replacingRejected rejected: String) async throws -> String {
        if let refreshTask { return try await refreshTask.value.accessToken }
        let tokens = try requireTokens()
        // Another caller refreshed since this token was handed out.
        if tokens.accessToken != rejected { return tokens.accessToken }
        return try await refreshed(from: tokens).accessToken
    }

    private func refreshed(from tokens: TokenSet) async throws -> TokenSet {
        if let refreshTask { return try await refreshTask.value }
        guard let endpoint, let refreshToken = tokens.refreshToken, tokens.isRefreshTokenUsable(at: now()) else {
            try endSession()
            throw DROPError.sessionExpired
        }
        let now = self.now
        let task = Task { () throws -> TokenSet in
            let token = try await endpoint.refresh(refreshToken: refreshToken)
            return TokenSet(token, issuedAt: now())
        }
        refreshTask = task
        defer { refreshTask = nil }
        do {
            let fresh = try await task.value
            try save(fresh)
            return fresh
        } catch let error as DROPError where error.code == .sessionExpired {
            try? endSession()
            throw error
        }
    }

    // MARK: Signing in and out

    public func startSignIn(scopes: [String]) async throws -> DeviceAuthorization {
        guard let endpoint else { throw DROPError.clientIDMissing }
        return try await endpoint.requestDeviceCode(scopes: scopes)
    }

    public func grantedScopes() async -> [String] {
        (try? loadTokens())?.scopes ?? []
    }

    public func finishSignIn(_ authorization: DeviceAuthorization) async throws {
        guard let endpoint else { throw DROPError.clientIDMissing }
        let deadline = now().addingTimeInterval(authorization.expiresIn)
        var interval = max(authorization.interval, 1)
        while true {
            try await sleep(.seconds(interval))
            try Task.checkCancellation()
            guard now() < deadline else { throw DROPError.signInCodeExpired }
            switch try await endpoint.pollForToken(deviceCode: authorization.deviceCode) {
            case .pending:
                continue
            case .slowDown(let newInterval):
                interval = newInterval ?? interval + 5
            case .authorized(let token):
                try save(TokenSet(token, issuedAt: now()))
                sessionEnded = false
                return
            }
        }
    }

    public func signOut() async throws {
        refreshTask?.cancel()
        refreshTask = nil
        try secrets.deleteData(for: Self.keychainAccount)
        cached = nil
        isLoaded = true
        sessionEnded = false
    }

    // MARK: Keychain

    private func requireTokens() throws -> TokenSet {
        guard let tokens = try loadTokens() else {
            throw sessionEnded ? DROPError.sessionExpired : DROPError.signedOut
        }
        return tokens
    }

    private func loadTokens() throws -> TokenSet? {
        if isLoaded { return cached }
        let data = try secrets.data(for: Self.keychainAccount)
        cached = data.flatMap { try? JSONDecoder().decode(TokenSet.self, from: $0) }
        isLoaded = true
        return cached
    }

    private func save(_ tokens: TokenSet) throws {
        try secrets.setData(JSONEncoder().encode(tokens), for: Self.keychainAccount)
        cached = tokens
        isLoaded = true
    }

    private func endSession() throws {
        cached = nil
        isLoaded = true
        sessionEnded = true
        try secrets.deleteData(for: Self.keychainAccount)
    }
}
