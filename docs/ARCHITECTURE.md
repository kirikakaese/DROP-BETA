# Architecture

DROP is a SwiftUI app with almost no code in the app target. Everything else lives in the local
Swift package `Packages/DROPKit`, split into modules with one job each:

| Module | What it does | Depends on |
| --- | --- | --- |
| `DROPCore` | Models (`Project`, `RepositorySlug`), `DROPError`, logging, paths. No UI, no networking. | – |
| `DROPGitHub` | The GitHub REST client. Tokens are passed in per request, never stored. | Core |
| `DROPRegistries` | Publishers for Homebrew, Scoop, GHCR and npm. | Core, GitHub |
| `DROPPersistence` | The metadata store (GRDB/SQLite): projects, drop history, audit log. No secrets. | Core, GRDB |
| `DROPServices` | Protocol-based services with live and in-memory implementations, and the `ServiceContainer`. | Core, GitHub, Registries, Persistence |
| `DROPUI` | SwiftUI views and their `@Observable` models. Talks to services through protocols only. | Core, Services |
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
