import DROPTestFixtures
import Foundation
import Testing

@testable import DROPCore

@Suite("SemanticVersion")
struct SemanticVersionTests {
    @Test func parsesTagsWithAndWithoutV() throws {
        let version = try #require(SemanticVersion("v1.2.3-beta.4+build.5"))
        #expect(version.major == 1 && version.minor == 2 && version.patch == 3)
        #expect(version.prerelease == ["beta", "4"])
        #expect(version.build == "build.5")
        #expect(version.betaNumber == 4)
        #expect(version.description == "1.2.3-beta.4+build.5")
        #expect(SemanticVersion("0.1.0")?.isPrerelease == false)
    }

    @Test(arguments: ["", "1", "1.2", "1.2.3.4", "01.2.3", "1.2.3-", "1.2.3-beta..1", "1.2.3+", "v", "a.b.c", "-1.2.3"])
    func refusesWhatIsNotSemver(_ text: String) {
        #expect(SemanticVersion(text) == nil)
    }

    @Test func ordersLikeSemverOrg() throws {
        // The example from semver.org §11.
        let ordered = [
            "1.0.0-alpha", "1.0.0-alpha.1", "1.0.0-alpha.beta", "1.0.0-beta", "1.0.0-beta.2", "1.0.0-beta.11",
            "1.0.0-rc.1", "1.0.0", "1.0.1", "1.1.0", "2.0.0",
        ].compactMap(SemanticVersion.init)
        #expect(ordered.count == 11)
        #expect(ordered.shuffled().sorted() == ordered)
        #expect(SemanticVersion("1.0.0+a") == SemanticVersion("1.0.0+b"))
    }

    @Test func bumpsAndMakesBetas() throws {
        let version = try #require(SemanticVersion("1.2.3-beta.1"))
        #expect(version.bumped(.patch).description == "1.2.4")
        #expect(version.bumped(.minor).description == "1.3.0")
        #expect(version.bumped(.major).description == "2.0.0")
        #expect(version.core.beta(2).description == "1.2.3-beta.2")
    }
}

@Suite("ConventionalCommit")
struct ConventionalCommitTests {
    @Test func readsTypeScopeSummaryAndPullRequest() {
        let commit = ConventionalCommit(sha: "abc1234", message: "feat(auth): sign in with github (#2)")
        #expect(commit.type == "feat")
        #expect(commit.scope == "auth")
        #expect(commit.summary == "sign in with github")
        #expect(commit.pullRequest == 2)
        #expect(!commit.isBreaking)
        #expect(commit.bump == .minor)
    }

    @Test func notesBreakingChangesFromTheMarkAndTheFooter() {
        let marked = ConventionalCommit(sha: "1", message: "refactor(core)!: rename the store")
        #expect(marked.isBreaking)
        #expect(marked.type == "refactor")
        #expect(marked.bump == .major)

        let footer = ConventionalCommit(sha: "2", message: "fix: keep tokens\n\nBREAKING CHANGE: sign in again")
        #expect(footer.isBreaking)
        #expect(footer.bump == .major)
    }

    @Test func keepsOtherSubjectsAsTheyAre() {
        let plain = ConventionalCommit(sha: "1", message: "Bring the README up to date (#22)")
        #expect(plain.type == nil)
        #expect(plain.summary == "Bring the README up to date")
        #expect(plain.pullRequest == 22)
        #expect(plain.bump == .patch)

        #expect(ConventionalCommit(sha: "2", message: "Merge pull request #18 from x/y").isMerge)
        #expect(ConventionalCommit(sha: "3", message: "feat(): empty scope").type == nil)
        #expect(ConventionalCommit(sha: "4", message: "fix:no space").type == nil)
    }
}

@Suite("VersionSuggestion")
struct VersionSuggestionTests {
    func commits(_ messages: String...) -> [ConventionalCommit] {
        messages.enumerated().map { ConventionalCommit(sha: "\($0.offset)", message: $0.element) }
    }

    @Test func startsAt010WithoutTags() {
        let suggestion = VersionSuggestion(tags: [], commits: commits("feat: first"))
        #expect(suggestion.latestRelease == nil)
        #expect(suggestion.tagName(for: suggestion.bump, beta: false) == "v0.1.0")
    }

    @Test func followsTheHighestBumpSinceTheLatestRelease() {
        let tags = ["v1.2.0", "v1.1.0", "v1.3.0-beta.1", "nightly"]
        let fixes = VersionSuggestion(tags: tags, commits: commits("fix: a", "docs: b"))
        #expect(fixes.latestRelease == "v1.2.0")
        #expect(fixes.bump == .patch)
        #expect(fixes.tagName(for: fixes.bump, beta: false) == "v1.2.1")

        let features = VersionSuggestion(tags: tags, commits: commits("fix: a", "feat: b"))
        #expect(features.bump == .minor)
        #expect(features.tagName(for: .minor, beta: false) == "v1.3.0")
        // v1.3.0-beta.1 exists, so the next beta is 2.
        #expect(features.tagName(for: .minor, beta: true) == "v1.3.0-beta.2")

        let breaking = VersionSuggestion(tags: tags, commits: commits("feat!: c"))
        #expect(breaking.bump == .major)
        #expect(breaking.tagName(for: .major, beta: true) == "v2.0.0-beta.1")
    }

    @Test func breakingChangesBeforeOneZeroBumpTheMinor() {
        let suggestion = VersionSuggestion(tags: ["v0.9.2"], commits: commits("feat(core)!: new store"))
        #expect(suggestion.bump == .minor)
        #expect(suggestion.tagName(for: suggestion.bump, beta: false) == "v0.10.0")
    }

    @Test func keepsTagsWithoutV() {
        let suggestion = VersionSuggestion(tags: ["1.0.0"], commits: commits("fix: a"))
        #expect(suggestion.tagName(for: .patch, beta: false) == "1.0.1")
    }
}

@Suite("Changelog")
struct ChangelogTests {
    let slug = Fixtures.slug("octocat/Hello-World")

    @Test func groupsByTypeWithLinksAndHidesChores() {
        let commits = [
            ConventionalCommit(sha: "aaaaaaa1", message: "feat(ui): add the drop sheet (#3)"),
            ConventionalCommit(sha: "bbbbbbb2", message: "fix: keep the selection"),
            ConventionalCommit(sha: "ccccccc3", message: "chore: bump GRDB"),
            ConventionalCommit(sha: "ddddddd4", message: "feat!: new plan format (#4)"),
            ConventionalCommit(sha: "eeeeeee5", message: "Tidy the README (#5)"),
            ConventionalCommit(sha: "fffffff6", message: "Merge branch 'main'"),
        ]
        let notes = Changelog.notes(for: commits, slug: slug, previousTag: "v1.0.0", newTag: "v2.0.0")
        #expect(notes == """
            ## Breaking Changes

            - new plan format ([#4](https://github.com/octocat/Hello-World/pull/4))

            ## Features

            - **ui:** add the drop sheet ([#3](https://github.com/octocat/Hello-World/pull/3))

            ## Fixes

            - keep the selection ([bbbbbbb](https://github.com/octocat/Hello-World/commit/bbbbbbb2))

            ## Other Changes

            - Tidy the README ([#5](https://github.com/octocat/Hello-World/pull/5))

            **Full Changelog**: [v1.0.0...v2.0.0](https://github.com/octocat/Hello-World/compare/v1.0.0...v2.0.0)

            """)
    }

    @Test func createsInsertsAndReplacesChangelogSections() {
        let date = Fixtures.referenceDate
        let day = date.formatted(.iso8601.year().month().day())
        let created = Changelog.updatingFile(nil, version: "v1.0.0", date: date, notes: "### Fixes\n\n- one\n")
        #expect(created == "# Changelog\n\n## v1.0.0 - \(day)\n\n### Fixes\n\n- one\n")

        let added = Changelog.updatingFile(created, version: "v1.1.0", date: date, notes: "### Features\n\n- two")
        #expect(added == """
            # Changelog

            ## v1.1.0 - \(day)

            ### Features

            - two

            ## v1.0.0 - \(day)

            ### Fixes

            - one

            """)

        let replaced = Changelog.updatingFile(added, version: "v1.1.0", date: date, notes: "### Features\n\n- three")
        #expect(replaced.components(separatedBy: "## v1.1.0").count == 2)
        #expect(replaced.contains("- three"))
        #expect(!replaced.contains("- two"))
        #expect(replaced.contains("- one"))
    }

    @Test func demotesHeadingsForTheChangelogFile() {
        #expect(Changelog.demotingHeadings("## Features\n\n- a #1") == "### Features\n\n- a #1")
    }
}
