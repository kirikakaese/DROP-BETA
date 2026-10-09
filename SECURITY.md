# Security Policy

The Distribution & Release Orchestration Platform (DROP) holds access to your GitHub account and
publishes software in your name, so security issues are taken seriously.

## Reporting a vulnerability

Please **do not** open a public issue for security problems.

Report vulnerabilities privately through GitHub's
[private vulnerability reporting](https://github.com/kirikakaese/DROP-BETA/security/advisories/new).
Include the affected version, steps to reproduce and the impact you expect.

You can expect an acknowledgement within 7 days. Fixes for confirmed issues are released as soon
as practical, and reporters are credited unless they prefer otherwise.

## Supported versions

Until 1.0, only the latest release receives security fixes.

## Threat model

### Assets

1. GitHub access and refresh tokens.
2. The integrity of what DROP publishes: tags, GitHub Releases, assets and registry manifests.
3. Files in your repositories and in your tap or bucket repositories that other automation owns.

### Trust boundaries

- **Trusted:** the logged-in macOS user and the OS (Keychain).
- **Untrusted:** GitHub and registry API responses, workflow logs, repository contents (workflow
  files, commit messages, manifests) and downloaded artifacts.

### In scope

| Threat | Mitigation |
| --- | --- |
| Token theft from disk | Tokens are stored only in the Keychain, never in files, `UserDefaults` or the metadata database. |
| Tokens leaking through logs or error messages | No telemetry. Unified logging never receives tokens; repository names are logged as `.private`. |
| Token sent to the wrong server | The GitHub client only builds requests below `https://api.github.com` and refuses paths that point elsewhere. |
| Publishing something you didn't intend | Every write is listed on the "Ready to Drop" plan first; nothing touches the network until you press **Drop**. |
| Racing or overwriting existing automation | Targets an existing workflow owns are marked External and only verified, never written. Switching one to Managed needs a confirmation that names the workflow. |
| Changes to shared repositories | Writes to tap and bucket repositories go through pull requests unless you opt into direct pushes per target. |
| Malicious API responses or repository contents | All external input is size-capped and decoded into typed models; commit messages and workflow files are parsed, never executed. |

### Out of scope

- An attacker running code as the same macOS user. They can ask the Keychain like DROP does,
  within what macOS allows.
- A compromised GitHub account or a compromised macOS installation.

## Signing and entitlements

Releases will be **ad-hoc signed** and not notarized: the project has no paid Apple Developer
account. macOS blocks the first launch until you allow it; compare the download with
`SHA256SUMS.txt` on the release page (Homebrew does this for you). Updates will only be installed
with a valid EdDSA signature from DROP's release key.

Every entitlement is documented in [docs/ENTITLEMENTS.md](docs/ENTITLEMENTS.md).
