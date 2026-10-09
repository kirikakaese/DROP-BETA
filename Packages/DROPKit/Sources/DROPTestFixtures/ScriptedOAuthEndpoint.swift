import DROPCore
import DROPGitHub
import Foundation
import os

/// An `OAuthEndpoint` with scripted answers. Refreshes can be held open to test concurrent callers.
public actor ScriptedOAuthEndpoint: OAuthEndpoint {
    public var deviceAuthorization = DeviceAuthorization(
        deviceCode: "device-code",
        userCode: "WDJB-MJHT",
        verificationURL: URL(filePath: "/device"),
        expiresIn: 900,
        interval: 5
    )
    /// Answers to successive polls; the last one repeats.
    public var pollResults: [Result<DevicePollResult, DROPError>] = []
    /// The answer to every refresh.
    public var refreshResult: Result<OAuthToken, DROPError> = .failure(.sessionExpired)

    public private(set) var refreshCount = 0
    public private(set) var refreshTokensSeen: [String] = []
    public private(set) var pollCount = 0

    private var refreshGates: [CheckedContinuation<Void, Never>] = []
    private var holdsRefreshes = false

    public init() {}

    public func setPollResults(_ results: [Result<DevicePollResult, DROPError>]) { pollResults = results }
    public func setRefreshResult(_ result: Result<OAuthToken, DROPError>) { refreshResult = result }
    public func setDeviceAuthorization(_ authorization: DeviceAuthorization) { deviceAuthorization = authorization }

    /// Makes refreshes wait until `releaseRefresh()` is called.
    public func holdRefreshes() { holdsRefreshes = true }

    public func releaseRefresh() {
        holdsRefreshes = false
        refreshGates.forEach { $0.resume() }
        refreshGates = []
    }

    public func requestDeviceCode(scopes: [String]) async throws -> DeviceAuthorization {
        deviceAuthorization
    }

    public func pollForToken(deviceCode: String) async throws -> DevicePollResult {
        pollCount += 1
        guard !pollResults.isEmpty else { return .pending }
        let result = pollResults.count > 1 ? pollResults.removeFirst() : pollResults[0]
        return try result.get()
    }

    public func refresh(refreshToken: String) async throws -> OAuthToken {
        refreshCount += 1
        refreshTokensSeen.append(refreshToken)
        if holdsRefreshes {
            await withCheckedContinuation { refreshGates.append($0) }
        }
        return try refreshResult.get()
    }
}

/// A clock tests can move forward.
public final class TestClock: Sendable {
    private let current: OSAllocatedUnfairLock<Date>

    public init(_ start: Date = Fixtures.referenceDate) {
        current = OSAllocatedUnfairLock(initialState: start)
    }

    public var now: Date { current.withLock { $0 } }

    public func advance(by seconds: TimeInterval) {
        current.withLock { $0 = $0.addingTimeInterval(seconds) }
    }
}
