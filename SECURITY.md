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
| Token theft from disk | Tokens are stored only in the Keychain (`…ThisDeviceOnly`, never synchronized), never in files, `UserDefaults` or the metadata database. |
| A client secret leaking from the app | There is none: DROP signs in with GitHub's device flow, which needs only the public Client ID. |
| Losing the session to a refresh race | Refresh tokens are single-use, so refreshing runs in one actor; concurrent requests wait for the running refresh instead of starting their own. |
| Tokens outliving their use | Access tokens expire and are refreshed shortly before; an expired or revoked refresh token ends the session and the tokens are deleted. |
| Tokens leaking through logs or error messages | No telemetry. Unified logging never receives tokens; repository names are logged as `.private`. |
| Token sent to the wrong server | The GitHub client only builds requests below `https://api.github.com` and refuses paths that point elsewhere. Redirects are followed only on the same host over HTTPS, and pagination links to other hosts are ignored. Requests use an ephemeral session without cookies or cache. |
| Publishing something you didn't intend | Every write is listed on the "Ready to Drop" plan first; nothing touches the network until you press **Drop**. |
| Racing or overwriting existing automation | Targets an existing workflow owns are marked External and only verified, never written. Switching one to Managed needs a confirmation that names the workflow. |
| Changes to shared repositories | Writes to tap and bucket repositories go through pull requests unless you opt into direct pushes per target. |
| Token sent to GitHub's storage | Logs and artifacts redirect to GitHub's storage; DROP follows those links without the token, over HTTPS only. |
| Crafted artifact archives | Artifacts are unpacked with `ditto` into a fresh temporary folder; links are removed and only regular files inside that folder are used. |
| Broader access than needed | The `workflow` scope is requested only when you let DROP add a workflow file, through a new sign-in that names it. |
| Someone at your unlocked Mac seeing your projects | The app lock hides the window behind Touch ID or the login password at launch, after the chosen idle time, on screen lock and on sleep. It only hides the window: a drop that is already running finishes. |
| Malicious API responses or repository contents | All external input is size-capped and decoded into typed models; commit messages and workflow files are parsed, never executed. |

### Out of scope

- An attacker running code as the same macOS user. They can ask the Keychain like DROP does,
  within what macOS allows.
- A compromised GitHub account or a compromised macOS installation.

## Signing and entitlements

Releases are **ad-hoc signed** and not notarized: the project has no paid Apple Developer
account. macOS blocks the first launch until you allow it; compare the download with
`SHA256SUMS.txt` on the release page (Homebrew does this for you). Updates (through
[Sparkle](https://sparkle-project.org)) are only installed with a valid EdDSA signature from
DROP's release key; builds not made by the release workflow have no key and never update
themselves. The private key exists only in the maintainer's Keychain and as a GitHub Actions
secret; see [RELEASING.md](RELEASING.md).

Every entitlement is documented in [docs/ENTITLEMENTS.md](docs/ENTITLEMENTS.md).
