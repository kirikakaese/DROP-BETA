import DROPCore
import DROPGitHub
import DROPServices
import DROPTestFixtures
import Foundation
import Testing

@testable import DROPUI

@MainActor
@Suite("AccountModel")
struct AccountModelTests {
    let endpoint = ScriptedOAuthEndpoint()
    let github = InMemoryGitHubService(user: GitHubUser(id: 7, login: "kirikakaese", name: "Kiri"))

    func makeModel() -> AccountModel {
        let auth = AuthService(endpoint: endpoint, secrets: InMemorySecretStore(), sleep: { _ in await Task.yield() })
        return AccountModel(services: .preview(auth: auth, github: github))
    }

    @Test func signsInShowsTheCodeAndLoadsTheUser() async throws {
        let model = makeModel()
        await model.load()
        #expect(model.phase == .signedOut)

        await endpoint.setPollResults([.success(.pending), .success(.authorized(OAuthToken(accessToken: "t")))])
        model.signIn()
        await model.signInTask?.value
        #expect(model.phase == .signedIn)
        #expect(model.user?.login == "kirikakaese")
    }

    @Test func showsTheCodeWhileWaitingAndCancelling() async throws {
        let model = makeModel()
        await model.load()
        model.signIn()
        while model.pendingAuthorization == nil { await Task.yield() }
        #expect(model.pendingAuthorization?.userCode == "WDJB-MJHT")

        model.cancelSignIn()
        #expect(model.phase == .signedOut)
        #expect(model.pendingAuthorization == nil)
    }

    @Test func anEndedSessionSwitchesToSignInAgain() async throws {
        let model = makeModel()
        await endpoint.setPollResults([.success(.authorized(OAuthToken(accessToken: "t")))])
        model.signIn()
        await model.signInTask?.value
        #expect(model.isSignedIn)

        #expect(model.filter(DROPError.sessionExpired) == nil)
        #expect(model.phase == .sessionExpired)
        #expect(model.user == nil)
        // Other errors are passed on to be shown.
        #expect(model.filter(DROPError.network(details: "offline"))?.code == .network)
    }

    @Test func signsOut() async throws {
        let model = makeModel()
        await endpoint.setPollResults([.success(.authorized(OAuthToken(accessToken: "t")))])
        model.signIn()
        await model.signInTask?.value
        await model.signOut()
        #expect(model.phase == .signedOut)
        #expect(model.user == nil)
    }

    @Test func reportsAFailedSignInAndGoesBack() async throws {
        let model = makeModel()
        await model.load()
        await endpoint.setPollResults([.failure(.signInCodeExpired)])
        model.signIn()
        await model.signInTask?.value
        #expect(model.phase == .signedOut)
        #expect(model.error == .signInCodeExpired)
    }
}
