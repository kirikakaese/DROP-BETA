import DROPTestFixtures
import Foundation
import Testing

@testable import DROPCore

@Suite("DROPError")
struct DROPErrorTests {
    @Test func bridgesToLocalizedError() {
        let error: any Error = DROPError.storageUnavailable(details: "disk I/O error")
        let localized = error as? LocalizedError
        #expect(localized?.errorDescription == "DROP could not open its project list.")
        #expect(localized?.recoverySuggestion?.isEmpty == false)
        #expect(localized?.failureReason == "disk I/O error")
    }

    @Test func namesTheDuplicateProject() {
        let error = DROPError.projectAlreadyAdded(Fixtures.slug("kirikakaese/SMP"))
        #expect(error.code == .alreadyExists)
        #expect(error.whatHappened.contains("kirikakaese/SMP"))
    }
}
