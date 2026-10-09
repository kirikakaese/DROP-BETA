import DROPCore
import DROPGitHub
import DROPServices
import Foundation
import Observation

/// The GitHub account: signing in with device flow, signing out, and noticing when the session ends.
@MainActor
@Observable
public final class AccountModel {
    public enum Phase: Equatable, Sendable {
        case loading
        case signedOut
        /// Showing the code until it is approved on GitHub.
        case waitingForApproval(DeviceAuthorization)
        case signedIn
        /// The session ended on its own; "Sign in again".
        case sessionExpired
    }

    public private(set) var phase: Phase = .loading
    public private(set) var user: GitHubUser?
    /// The last error, shown as an alert.
    public var error: DROPError?

    @ObservationIgnored var signInTask: Task<Void, Never>?
    /// Where to go back to when signing in is cancelled or fails.
    @ObservationIgnored private var phaseBeforeSignIn: Phase = .signedOut
    private let services: ServiceContainer

    public init(services: ServiceContainer) {
        self.services = services
    }

    public var canSignIn: Bool { services.auth.canSignIn }
    public var isSignedIn: Bool { phase == .signedIn }

    public var pendingAuthorization: DeviceAuthorization? {
        if case .waitingForApproval(let authorization) = phase { authorization } else { nil }
    }

    public func load() async {
        switch await services.auth.state() {
        case .signedIn:
            phase = .signedIn
            await loadUser()
        case .signedOut:
            phase = .signedOut
        case .sessionExpired:
            phase = .sessionExpired
        }
    }

    /// Starts device flow. The code appears in `pendingAuthorization` until it is approved.
    public func signIn(scopes: [String] = OAuthConfiguration.signInScopes) {
        if pendingAuthorization == nil {
            switch phase {
            case .signedIn, .sessionExpired: phaseBeforeSignIn = phase
            default: phaseBeforeSignIn = .signedOut
            }
        }
        signInTask?.cancel()
        signInTask = Task { await runSignIn(scopes: scopes) }
    }

    /// Whether the account may change workflow files. `true` when GitHub didn't list scopes.
    public func canChangeWorkflows() async -> Bool {
        let scopes = await services.auth.grantedScopes()
        return scopes.isEmpty || scopes.contains("workflow")
    }

    public func cancelSignIn() {
        signInTask?.cancel()
        signInTask = nil
        if case .waitingForApproval = phase { phase = phaseBeforeSignIn }
    }

    public func signOut() async {
        do {
            try await services.auth.signOut()
            user = nil
            phase = .signedOut
        } catch {
            self.error = .wrapping(error)
        }
    }

    /// Routes an error from a GitHub call. An ended session switches to "Sign in again" and returns
    /// `nil`; anything else is returned for the caller to show.
    public func filter(_ error: any Error) -> DROPError? {
        if error is CancellationError { return nil }
        let error = DROPError.wrapping(error)
        switch error.code {
        case .sessionExpired:
            user = nil
            phase = .sessionExpired
            return nil
        case .signedOut:
            user = nil
            phase = .signedOut
            return nil
        default:
            return error
        }
    }

    private func runSignIn(scopes: [String]) async {
        let previous = phaseBeforeSignIn
        do {
            let authorization = try await services.auth.startSignIn(scopes: scopes)
            phase = .waitingForApproval(authorization)
            try await services.auth.finishSignIn(authorization)
            try Task.checkCancellation()
            phase = .signedIn
            await loadUser()
        } catch is CancellationError {
            if case .waitingForApproval = phase { phase = previous }
        } catch {
            phase = previous
            self.error = .wrapping(error)
        }
    }

    private func loadUser() async {
        do {
            user = try await services.github.currentUser()
        } catch {
            self.error = filter(error)
        }
    }
}
