import Testing

@testable import DROPCore

@Suite("WorkflowTriggers")
struct WorkflowTriggersTests {
    @Test func readsTagPushAndDispatchFromTheBlockForm() {
        let triggers = WorkflowTriggers(yaml: """
            name: Release
            # Push a tag like v0.9.0 to release.
            on:
              push:
                tags:
                  - "v*"
                  - 'release-*'
              workflow_dispatch:
                inputs:
                  dry_run:
                    type: boolean

            jobs:
              push:
                runs-on: macos-15
            """)
        #expect(triggers.tagPush)
        #expect(triggers.dispatch)
        #expect(!triggers.release)
        #expect(triggers.tagPatterns == ["v*", "release-*"])
        #expect(triggers.startsOnPush(of: "v1.2.3"))
        #expect(triggers.startsOnPush(of: "release-7"))
        #expect(!triggers.startsOnPush(of: "nightly"))
    }

    @Test func readsInlineTagLists() {
        let triggers = WorkflowTriggers(yaml: "on:\n  push:\n    branches: [main]\n    tags: [\"v*.*.*\"]\n")
        #expect(triggers.tagPatterns == ["v*.*.*"])
        #expect(triggers.startsOnPush(of: "v1.2.3"))
        #expect(!triggers.startsOnPush(of: "v1.2"))
    }

    @Test func branchFiltersAloneDoNotStartOnTags() {
        let triggers = WorkflowTriggers(yaml: "on:\n  push:\n    branches: [main]\n  pull_request:\n")
        #expect(!triggers.tagPush)
        #expect(!triggers.dispatch)
    }

    @Test func pushWithoutFiltersAndTheShortForms() {
        #expect(WorkflowTriggers(yaml: "on:\n  push:\n  release:\n    types: [published]\n").tagPush)
        #expect(WorkflowTriggers(yaml: "on:\n  release:\n    types: [published]\n").release)
        let list = WorkflowTriggers(yaml: "on: [push, workflow_dispatch]\njobs: {}\n")
        #expect(list.tagPush && list.dispatch)
        #expect(WorkflowTriggers(yaml: "on: pull_request\n") == WorkflowTriggers())
        #expect(WorkflowTriggers(yaml: "") == WorkflowTriggers())
    }

    @Test(arguments: [
        ("v*", "v1.0.0", true), ("v*", "app/v1", false), ("**", "app/v1", true), ("v1.*", "v1.2", true),
        ("v[0-9]", "v[0-9]", true), ("v1.?", "v1.2", false),
    ])
    func matchesGitHubsGlobs(pattern: String, tag: String, expected: Bool) {
        #expect(WorkflowTriggers.glob(pattern, matches: tag) == expected)
    }
}
