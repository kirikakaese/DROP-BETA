import DROPCore
import DROPTestFixtures
import Foundation
import Testing
import os

@testable import DROPGitHub

@Suite("GitHubOAuthEndpoint")
struct OAuthEndpointTests {
    func makeEndpoint(_ responder: @escaping FakeTransport.Responder) -> (GitHubOAuthEndpoint, FakeTransport) {
        let transport = FakeTransport(responder)
        return (GitHubOAuthEndpoint(clientID: "Iv1.test", transport: transport, userAgent: "DROP"), transport)
    }

    @Test func requestsADeviceCodeWithTheClientIDAndScopesOnly() async throws {
        let (endpoint, transport) = makeEndpoint { _ in
            (200, [:], FakeTransport.json("""
                {"device_code": "dc", "user_code": "WDJB-MJHT", "verification_uri": "https://github.com/login/device",
                 "expires_in": 899, "interval": 5}
                """))
        }
        let authorization = try await endpoint.requestDeviceCode(scopes: ["repo", "workflow"])
        #expect(authorization.userCode == "WDJB-MJHT")
        #expect(authorization.verificationURL.absoluteString == "https://github.com/login/device")
        #expect(authorization.expiresIn == 899)
        #expect(authorization.interval == 5)

        let request = try #require(transport.requests.first)
        #expect(request.url?.absoluteString == "https://github.com/login/device/code")
        #expect(request.httpMethod == "POST")
        #expect(request.value(forHTTPHeaderField: "Accept") == "application/json")
        #expect(FakeTransport.formFields(of: request) == ["client_id": "Iv1.test", "scope": "repo workflow"])
    }

    @Test func refusesAVerificationAddressThatIsNotHTTPS() async {
        let (endpoint, _) = makeEndpoint { _ in
            (200, [:], FakeTransport.json(#"{"device_code": "dc", "user_code": "C", "verification_uri": "http://x"}"#))
        }
        await #expect(throws: DROPError.self) { try await endpoint.requestDeviceCode(scopes: ["repo"]) }
    }

    @Test func pollsAndReadsEveryAnswer() async throws {
        let answers = [
            #"{"error": "authorization_pending"}"#,
            #"{"error": "slow_down", "interval": 10}"#,
            #"{"access_token": "ghu_x", "expires_in": 28800, "refresh_token": "ghr_y", "#
                + #""refresh_token_expires_in": 15811200, "token_type": "bearer", "scope": "repo,workflow"}"#,
        ]
        let counter = Counter()
        let (endpoint, transport) = makeEndpoint { _ in (200, [:], FakeTransport.json(answers[counter.next()])) }

        #expect(try await endpoint.pollForToken(deviceCode: "dc") == .pending)
        #expect(try await endpoint.pollForToken(deviceCode: "dc") == .slowDown(interval: 10))
        let expected = OAuthToken(
            accessToken: "ghu_x",
            accessTokenExpiresIn: 28_800,
            refreshToken: "ghr_y",
            refreshTokenExpiresIn: 15_811_200,
            scopes: ["repo", "workflow"]
        )
        #expect(try await endpoint.pollForToken(deviceCode: "dc") == .authorized(expected))
        #expect(FakeTransport.formFields(of: transport.requests[0]) == [
            "client_id": "Iv1.test",
            "device_code": "dc",
            "grant_type": "urn:ietf:params:oauth:grant-type:device_code",
        ])
    }

    @Test(arguments: ["expired_token", "access_denied", "device_flow_disabled", "incorrect_client_credentials"])
    func reportsFailedSignIns(_ code: String) async {
        let (endpoint, _) = makeEndpoint { _ in (200, [:], FakeTransport.json(#"{"error": "\#(code)"}"#)) }
        do {
            _ = try await endpoint.pollForToken(deviceCode: "dc")
            Issue.record("Expected an error")
        } catch let error as DROPError {
            #expect(error.code == .authorizationFailed)
        } catch {
            Issue.record("Unexpected error \(error)")
        }
    }

    @Test func refreshesWithoutAClientSecret() async throws {
        let (endpoint, transport) = makeEndpoint { _ in
            (200, [:], FakeTransport.json(#"{"access_token": "ghu_new", "refresh_token": "ghr_new"}"#))
        }
        let token = try await endpoint.refresh(refreshToken: "ghr_old")
        #expect(token.accessToken == "ghu_new")
        #expect(token.refreshToken == "ghr_new")
        let fields = FakeTransport.formFields(of: try #require(transport.requests.first))
        #expect(fields == ["client_id": "Iv1.test", "grant_type": "refresh_token", "refresh_token": "ghr_old"])
        #expect(fields["client_secret"] == nil)
    }

    @Test func aRejectedRefreshTokenEndsTheSession() async {
        let (endpoint, _) = makeEndpoint { _ in (200, [:], FakeTransport.json(#"{"error": "bad_refresh_token"}"#)) }
        await #expect(throws: DROPError.sessionExpired) { try await endpoint.refresh(refreshToken: "ghr_old") }
    }

    @Test func neverPrintsTokens() {
        let token = OAuthToken(accessToken: "ghu_secret", refreshToken: "ghr_secret")
        #expect(!token.description.contains("secret"))
        #expect(!String(describing: token).contains("secret"))
    }

    @Test func formEncodingEscapesReservedCharacters() {
        #expect(FormEncoding.encode(["b": "a b&c=d", "a": "x/y"]) == "a=x%2Fy&b=a%20b%26c%3Dd")
    }
}

private final class Counter: Sendable {
    private let value = OSAllocatedUnfairLock(initialState: 0)

    func next() -> Int {
        value.withLock { value in
            defer { value += 1 }
            return value
        }
    }
}
