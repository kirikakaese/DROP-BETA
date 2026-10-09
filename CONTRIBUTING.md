# Contributing to DROP

Thanks for your interest in the Distribution & Release Orchestration Platform.

## Development setup

1. Install Xcode 16 or later (the Command Line Tools alone cannot run the tests) and
   [XcodeGen](https://github.com/yonaskolb/XcodeGen).
2. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set the GitHub Client ID
   ([SETUP.md](SETUP.md)) and optionally your Team ID. The file is git-ignored; never commit it.
3. Run `xcodegen generate` and open `DROP.xcodeproj`, or work on the package directly with
   `swift build --package-path Packages/DROPKit`.

## Before opening a pull request

```sh
swift test --package-path Packages/DROPKit
swiftlint lint --strict
xcrun swift-format lint --recursive App Packages/DROPKit/Sources Packages/DROPKit/Tests
```

To format code in place: `xcrun swift-format format --in-place --recursive App Packages/DROPKit`.

## Rules

- **No network in tests.** Services have in-memory implementations; use those.
- **Never put tokens in logs, the metadata database, `UserDefaults` or error messages.** They
  live in the Keychain only.
- **Every user-facing string goes through the String Catalog** (`App/Resources/Localizable.xcstrings`)
  with a German translation. The Strings workflow fails otherwise.
- **The main action is called "Drop"** (Drop, Drop v1.2.3, Dropping…, Dropped, Drop a Beta).
  GitHub's own objects keep their names: GitHub Release, release notes, prerelease.
- **The repository slug lives only in `Config/Repo.xcconfig`.** Code reads it from Info.plist,
  scripts from `scripts/repo_slug.sh`.

## Commits and pull requests

Pull requests are squash-merged with their title as the commit message, so the title must be a
[Conventional Commit](https://www.conventionalcommits.org/) line: `type(scope): summary`,
imperative, lowercase, no trailing period, at most 72 characters. Types: `feat`, `fix`,
`refactor`, `perf`, `test`, `docs`, `build`, `ci`, `chore`, `style`, `revert`. Scopes: `core`,
`github`, `auth`, `registries`, `persistence`, `services`, `ui`, `app`, `release`, `ci`, `docs`,
`l10n`.
