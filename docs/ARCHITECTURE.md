# Architecture

DROP is a SwiftUI app with almost no code in the app target. Everything else lives in the local
Swift package `Packages/DROPKit`, split into modules with one job each:

| Module | What it does | Depends on |
| --- | --- | --- |
| `DROPCore` | Models (`Project`, `RepositorySlug`), `DROPError`, logging, paths. No UI, no networking. | – |
| `DROPGitHub` | The GitHub REST client. Tokens are passed in per request, never stored. | Core |
| `DROPRegistries` | Updates Homebrew casks and formulas and Scoop manifests, picks the asset they point at, finds files another automation writes. Text only, no I/O. | Core, GitHub |
| `DROPPersistence` | The metadata store (GRDB/SQLite): projects, drop history, audit log, destination and registry settings. No secrets. | Core, GRDB |
| `DROPServices` | Protocol-based services with live and in-memory implementations, and the `ServiceContainer`. | Core, GitHub, Registries, Persistence |
| `DROPUI` | SwiftUI views and their `@Observable` models. Talks to services through protocols only. | Core, GitHub, Registries, Services |
| `DROPTestFixtures` | Sample data for the tests. Never ships in the app. | Core |

The app target (`App/Sources`) creates the live `ServiceContainer`, the models and the scenes.

## Rules

- **Services are protocols.** Every service has a live implementation and an in-memory one;
  tests and previews use the in-memory ones and never touch the network or your real data.
- **Secrets only in the Keychain.** The metadata database, logs and errors never contain tokens.
- **One owner for tokens.** `AuthService` (an actor in `DROPServices`) signs in with device flow,
  keeps the tokens in the Keychain and refreshes them. `GitHubClient` asks it for a token for each
  request and, after a 401, for a replacement once. Because refresh tokens are single-use, a
  refresh that is already running is shared by every caller that needs one.
- **Nothing is written before the plan.** Any action that changes something on GitHub or in a
  registry is first listed on the "Ready to Drop" plan and only runs after you press **Drop**.
  `DropService.plan` only reads (the existing GitHub Release, whether the tag exists) and computes
  checksums locally; `DropService.execute` is the only code that writes, and it records every step
  in the project's history and audit log.
- **One repository slug.** DROP's own repository is named only in `Config/Repo.xcconfig`. It
  reaches the code through the `DROPRepositorySlug` Info.plist key (`AppRepository.slug()`) and
  the scripts through `scripts/repo_slug.sh`. CI checks that it matches the repository it runs in.
- **Changes to repositories go through pull requests.** `ChangelogService` updates CHANGELOG.md
  on a new `changelog/<tag>` branch and opens a pull request; it never pushes to the default branch.
  Its commits use the signed-in account's `ID+login@users.noreply.github.com` address, a
  Conventional Commit message and no trailer.
- **Existing automation wins.** `AutomationDetector` reads workflows and tool configuration
  (GoReleaser, semantic-release, release-please, changesets) and marks every destination it finds
  automated as External. DROP never writes to an External destination: when a workflow owns the
  GitHub Release, a drop only pushes the tag (or starts the workflow on it), waits for the run and
  checks the result. Taking a destination over needs a confirmation that names its automation.
- **Registries without tokens.** For a Managed Homebrew tap or Scoop bucket, `RegistryService`
  changes one file (`version`, `sha256`/`hash`, `url`) on a `drop/<name>-<version>` branch and
  opens a pull request, or commits to the default branch if you chose that. Before anything is
  written, the plan checks that no workflow of the project or the tap mentions the file, so a file
  another automation writes (like a cask a release workflow bumps) is never touched. Betas and
  drafts stay out of taps and buckets. GHCR and npm are published by a workflow in the project that
  DROP starts on the tag (`WorkflowTemplate.ghcr` and `.npm` can be added through a pull request);
  it signs in with the workflow's own `GITHUB_TOKEN` or npm's trusted publishing, so DROP never
  holds a registry token. **Try It** runs the same code as a drop without the write.
