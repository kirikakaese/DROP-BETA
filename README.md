# Distribution & Release Orchestration Platform (DROP)

**DROP** (short for **D**istribution & **R**elease **O**rchestration **P**latform) is a native
macOS app for shipping software. It creates GitHub Releases, writes changelogs and suggests the
next version, triggers and watches your GitHub Actions builds, and publishes to Homebrew, Scoop,
GHCR and npm. It never fights the automation you already have: anything a workflow already does,
DROP watches and verifies instead of doing it twice.

> **Status:** early development (0.1). Signing in with GitHub and adding projects work; the
> other features below are being built one by one. Please
> [open an issue](https://github.com/kirikakaese/DROP-BETA/issues) if something looks wrong.

## Features (planned)

- **Drop a version:** create the tag and the GitHub Release, as a draft or a prerelease ("Drop a
  Beta"), upload assets with `SHA256SUMS.txt`, and verify the checksums after uploading.
  Dropping the same tag again replaces its assets instead of failing.
- **Changelog and versions:** reads Conventional Commits since the last tag, suggests a major,
  minor or patch bump (or the next `-beta.N`), groups the notes by type and links the pull
  requests. `CHANGELOG.md` updates arrive as a pull request, never as a push to `main`.
- **Builds on GitHub Actions:** DROP doesn't build anything on your Mac. It dispatches or
  tag-triggers your release workflow, shows runs, jobs and logs live, and attaches the
  artifacts to the drop.
- **Package registries:** Homebrew tap (formula and cask), Scoop bucket, GHCR and npm. Each target
  is **Managed** (DROP does it), **External** (an existing workflow does it; DROP only verifies)
  or **Off**.
- **Ready to Drop:** before anything is written, one screen lists every step and who performs
  it, DROP or the named workflow. Nothing touches the network until you press **Drop**.
- **Sign in with GitHub:** device flow, tokens only in the Keychain, refreshed before they
  expire.
- **History:** every drop and every step is kept per project, without secrets.

## Requirements

- macOS 14 Sonoma or later, Apple Silicon or Intel.

## Building from source

1. Install Xcode 16 or later and [XcodeGen](https://github.com/yonaskolb/XcodeGen).
2. Copy `Config/Local.xcconfig.example` to `Config/Local.xcconfig` and set the GitHub Client ID
   (and optionally your Team ID). [SETUP.md](SETUP.md) walks you through it.
3. Run `xcodegen generate` and open `DROP.xcodeproj`.

See [CONTRIBUTING.md](CONTRIBUTING.md) for tests and linting, and
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for how the code is organized.

## Security

See [SECURITY.md](SECURITY.md) for how to report a vulnerability and what DROP protects.

## License

DROP is free software, released under the GNU General Public License v3.0
(SPDX: `GPL-3.0-only`). See [LICENSE](LICENSE).
