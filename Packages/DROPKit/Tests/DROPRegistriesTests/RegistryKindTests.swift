import Testing

@testable import DROPRegistries

@Suite("RegistryKind")
struct RegistryKindTests {
    @Test func coversTheFourTargetsInOrder() {
        #expect(RegistryKind.allCases == [.homebrewTap, .scoopBucket, .ghcr, .npm])
    }

    @Test func everyKindHasATitleAndAnIcon() {
        for kind in RegistryKind.allCases {
            #expect(!kind.title.isEmpty)
            #expect(!kind.systemImage.isEmpty)
        }
    }

    @Test func identifiersAreStable() {
        // Stored per project, so renaming a case would lose the setting.
        #expect(RegistryKind.allCases.map(\.rawValue) == ["homebrewTap", "scoopBucket", "ghcr", "npm"])
    }
}
