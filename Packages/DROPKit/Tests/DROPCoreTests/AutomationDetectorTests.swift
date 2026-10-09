import Testing

@testable import DROPCore

@Suite("AutomationDetector")
struct AutomationDetectorTests {
    /// Shaped like SMP's release.yml: it creates the GitHub Release and writes the tap's cask.
    static let smpRelease = """
        on:
          push:
            tags: ["v*"]
        jobs:
          release:
            steps:
              - run: gh release create "$TAG" dist/*.dmg --title "SMP $VERSION"
              - name: Update the Homebrew tap
                run: git clone https://x-access-token:${TAP_TOKEN}@github.com/kirikakaese/homebrew-tap.git tap
        """

    @Test func findsTheGitHubReleaseAndTheTapInAWorkflow() {
        let findings = AutomationDetector.findings(in: [".github/workflows/release.yml": Self.smpRelease])
        #expect(findings.map(\.destination) == [.githubRelease, .homebrewTap])
        let owners = Set(findings.map(\.owner))
        #expect(owners == [".github/workflows/release.yml"])
        #expect(findings.first?.evidence == "gh release create")
    }

    @Test func readsWhatGoReleaserPublishes() {
        let config = """
            builds:
              - goos: [linux, darwin]
            brews:
              - repository: { owner: me, name: homebrew-tap }
            scoops:
              - repository: { owner: me, name: scoop-bucket }
            dockers:
              - image_templates: ["ghcr.io/me/app:{{ .Version }}"]
            """
        let findings = AutomationDetector.findings(in: [".goreleaser.yaml": config])
        #expect(Set(findings.map(\.destination)) == [.githubRelease, .homebrewTap, .scoopBucket, .ghcr])
    }

    @Test func ignoresWorkflowsThatOnlyBuildAndTest() {
        let ci = "on: [push]\njobs:\n  test:\n    steps:\n      - run: swift test\n"
        #expect(AutomationDetector.findings(in: [".github/workflows/ci.yml": ci]).isEmpty)
        // Pulling an image from ghcr.io isn't publishing to it.
        let pull = "jobs:\n  t:\n    container: ghcr.io/me/builder:1\n"
        #expect(AutomationDetector.findings(in: [".github/workflows/ci.yml": pull]).isEmpty)
    }

    @Test func defaultsToExternalWhenAutomationIsFoundAndKeepsWhatYouChose() {
        let findings = AutomationDetector.findings(in: [".github/workflows/release.yml": Self.smpRelease])
        let defaults = AutomationDetector.settings(stored: [], findings: findings)
        #expect(defaults.map(\.mode) == [.external, .external, .off, .off, .off])
        #expect(defaults[1].ownerName == "release.yml")

        let chosen = DestinationSetting(destination: .githubRelease, mode: .managed)
        let settings = AutomationDetector.settings(stored: [chosen], findings: findings)
        #expect(settings[0].mode == .managed)

        let none = AutomationDetector.settings(stored: [], findings: [])
        #expect(none.map(\.mode) == [.managed, .off, .off, .off, .off])
    }

    @Test func namesWhoPerformsEachStep() {
        #expect(DropStep.pushTag(tag: "v1", target: "main").performer == .drop)
        let waiting = DropStep.awaitWorkflow(name: "release.yml", workflowID: 1, tag: "v1")
        #expect(waiting.performer == .automation("release.yml"))
        let tap = DropStep.leaveToAutomation(destination: .homebrewTap, owner: ".github/workflows/release.yml")
        #expect(tap.performer.title == "release.yml")
        #expect(!tap.writes)
    }
}
