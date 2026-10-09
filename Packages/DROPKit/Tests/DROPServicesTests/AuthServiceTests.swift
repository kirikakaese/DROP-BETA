import DROPCore
import DROPGitHub
import DROPTestFixtures
import Foundation
import Testing

@testable import DROPServices

@Suite("AuthService")
struct AuthServiceTests {
    let clock = TestClock()
    let endpoint = ScriptedOAuthEndpoint()
    let secrets = InMemorySecretStore()

    func makeService(leeway: TimeInterval = 300) -> AuthService {
        let clock = self.clock
        return AuthService(
            endpoint: endpoint,
            secrets: secrets,
            now: { clock.now },
            sleep: { _ in },
            refreshLeeway: leeway
        )
    }

    /// Signs in with an access token valid for 8 hours and a refresh token valid for 6 months.
    func signIn(_ service: AuthService, access: String = "access-1", refresh: String? = "refresh-1") async throws {
        await endpoint.setPollResults([
            .success(.pending),
            .success(.authorized(OAuthToken(
                accessToken: access,
                accessTokenExpiresIn: refresh == nil ? nil : 28_800,
                refreshToken: refresh,
                refreshTokenExpiresIn: refresh == nil ? nil : 15_811_200,
                scopes: ["repo"]
            ))),
        ])
        let authorization = try await service.startSignIn()
        try await service.finishSignIn(authorization)
    }

    static func refreshed(_ access: String, _ refresh: String) -> OAuthToken {
        OAuthToken(
            accessToken: access,
            accessTokenExpiresIn: 28_800,
            refreshToken: refresh,
            refreshTokenExpiresIn: 15_811_200
        )
    }

    // MARK: Signing in

    @Test func signsInWithDeviceFlowAndKeepsTokensInTheKeychainOnly() async throws {
        let service = makeService()
        #expect(await service.state() == .signedOut)
        await #expect(throws: DROPError.self) { try await service.accessToken() }

        try await signIn(service)
        #expect(await service.state() == .signedIn)
        #expect(try await service.accessToken() == "access-1")
        #expect(await endpoint.pollCount == 2)

        let stored = try #require(try secrets.data(for: AuthService.keychainAccount))
        let tokens = try JSONDecoder().decode(TokenSet.self, from: stored)
        #expect(tokens.refreshToken == "refresh-1")
        #expect(tokens.accessTokenExpiresAt == clock.now.addingTimeInterval(28_800))
    }

    @Test func slowsDownWhenGitHubAsksAndGivesUpWhenTheCodeExpires() async throws {
        let sleeps = SleepRecorder()
        let clock = self.clock
        let service = AuthService(
            endpoint: endpoint,
            secrets: secrets,
            now: { clock.now },
            sleep: { duration in
                await sleeps.record(duration)
                clock.advance(by: Double(duration.components.seconds))
            }
        )
        await endpoint.setPollResults([.success(.slowDown(interval: nil)), .success(.pending)])
        let authorization = try await service.startSignIn()
        await #expect(throws: DROPError.signInCodeExpired) { try await service.finishSignIn(authorization) }
        let intervals = await sleeps.seconds
        #expect(intervals.prefix(3) == [5, 10, 10])
        #expect(await service.state() == .signedOut)
    }

    @Test func reportsADeniedSignIn() async throws {
        let service = makeService()
        let denied = DROPError(.authorizationFailed, whatHappened: "Signing in was cancelled on GitHub.")
        await endpoint.setPollResults([.failure(denied)])
        let authorization = try await service.startSignIn()
        await #expect(throws: denied) { try await service.finishSignIn(authorization) }
        #expect(await service.state() == .signedOut)
    }

    @Test func cannotSignInWithoutAClientID() async {
        let service = AuthService(endpoint: nil, secrets: secrets)
        #expect(!service.canSignIn)
        await #expect(throws: DROPError.clientIDMissing) { try await service.startSignIn() }
    }

    // MARK: Refreshing

    @Test func refreshesShortlyBeforeTheAccessTokenExpires() async throws {
        let service = makeService()
        try await signIn(service)
        await endpoint.setRefreshResult(.success(Self.refreshed("access-2", "refresh-2")))

        clock.advance(by: 28_800 - 600)
        #expect(try await service.accessToken() == "access-1")
        #expect(await endpoint.refreshCount == 0)

        clock.advance(by: 400)
        #expect(try await service.accessToken() == "access-2")
        #expect(try await service.accessToken() == "access-2")
        #expect(await endpoint.refreshCount == 1)
        #expect(await endpoint.refreshTokensSeen == ["refresh-1"])
    }

    @Test func concurrentCallersShareOneRefresh() async throws {
        let service = makeService()
        try await signIn(service)
        await endpoint.setRefreshResult(.success(Self.refreshed("access-2", "refresh-2")))
        await endpoint.holdRefreshes()
        clock.advance(by: 28_800)

        let tokens = try await withThrowingTaskGroup(of: String.self) { group in
            for index in 0..<20 {
                group.addTask {
                    if index.isMultiple(of: 2) {
                        return try await service.accessToken()
                    }
                    return try await service.accessToken(replacingRejected: "access-1")
                }
            }
            while await endpoint.refreshCount == 0 { await Task.yield() }
            // Give the other callers time to pile up behind the running refresh.
            for _ in 0..<100 { await Task.yield() }
            await endpoint.releaseRefresh()
            return try await group.reduce(into: [String]()) { $0.append($1) }
        }

        #expect(tokens.count == 20)
        #expect(Set(tokens) == ["access-2"])
        // A refresh token is single-use; a second refresh would have signed you out.
        #expect(await endpoint.refreshCount == 1)
    }

    @Test func aRejectedTokenIsReplacedOnceAndALaterRejectionOfTheOldOneReusesIt() async throws {
        let service = makeService()
        try await signIn(service)
        await endpoint.setRefreshResult(.success(Self.refreshed("access-2", "refresh-2")))

        #expect(try await service.accessToken(replacingRejected: "access-1") == "access-2")
        // A request that started with the old token fails late: it gets the new one, no refresh.
        #expect(try await service.accessToken(replacingRejected: "access-1") == "access-2")
        #expect(await endpoint.refreshCount == 1)
    }

    @Test func endsTheSessionWhenTheRefreshTokenIsRevoked() async throws {
        let service = makeService()
        try await signIn(service)
        await endpoint.setRefreshResult(.failure(.sessionExpired))
        clock.advance(by: 28_800)

        await #expect(throws: DROPError.sessionExpired) { try await service.accessToken() }
        #expect(await service.state() == .sessionExpired)
        #expect(try secrets.data(for: AuthService.keychainAccount) == nil)
        await #expect(throws: DROPError.sessionExpired) { try await service.accessToken() }
    }

    @Test func endsTheSessionWhenTheRefreshTokenHasExpired() async throws {
        let service = makeService()
        try await signIn(service)
        clock.advance(by: 15_811_200 + 1)

        #expect(await service.state() == .sessionExpired)
        await #expect(throws: DROPError.sessionExpired) { try await service.accessToken() }
        #expect(await endpoint.refreshCount == 0)
    }

    @Test func keepsTheOldTokenWhenAnEarlyRefreshFailsOffline() async throws {
        let service = makeService()
        try await signIn(service)
        await endpoint.setRefreshResult(.failure(.network(details: "offline")))
        clock.advance(by: 28_800 - 60)

        #expect(try await service.accessToken() == "access-1")
        #expect(await service.state() == .signedIn)
    }

    @Test func aRejectedTokenThatNeverExpiresEndsTheSession() async throws {
        let service = makeService()
        try await signIn(service, access: "classic", refresh: nil)
        #expect(try await service.accessToken() == "classic")

        await #expect(throws: DROPError.sessionExpired) {
            try await service.accessToken(replacingRejected: "classic")
        }
        #expect(await endpoint.refreshCount == 0)
        #expect(await service.state() == .sessionExpired)
    }

    @Test func signingOutForgetsTheTokens() async throws {
        let service = makeService()
        try await signIn(service)
        try await service.signOut()
        #expect(await service.state() == .signedOut)
        #expect(try secrets.data(for: AuthService.keychainAccount) == nil)
        await #expect(throws: DROPError.signedOut) { try await service.accessToken() }
    }

    @Test func signingInAgainAfterTheSessionEndedWorks() async throws {
        let service = makeService()
        try await signIn(service)
        await endpoint.setRefreshResult(.failure(.sessionExpired))
        clock.advance(by: 28_800)
        _ = try? await service.accessToken()
        #expect(await service.state() == .sessionExpired)

        try await signIn(service, access: "access-3", refresh: "refresh-3")
        #expect(await service.state() == .signedIn)
        #expect(try await service.accessToken() == "access-3")
    }
}

private actor SleepRecorder {
    private(set) var seconds: [Int64] = []

    func record(_ duration: Duration) {
        seconds.append(duration.components.seconds)
    }
}
