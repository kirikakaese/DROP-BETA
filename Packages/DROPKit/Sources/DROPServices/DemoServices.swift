#if DEBUG
import DROPCore
import DROPGitHub
import DROPPersistence
import Foundation

/// The account state the demo services start in.
public enum DemoAccount: Sendable {
    case signedIn
    case signedOut
    /// Signed in once, but the refresh token has expired.
    case sessionEnded
}

extension ServiceContainer {
    /// Services with sample data, for the screenshots CI takes of every branch. Debug builds only;
    /// never touches disk, the Keychain or the network.
    public static func demo(now: Date = Date(), account: DemoAccount = .signedIn) -> ServiceContainer {
        let day: TimeInterval = 86_400
        let smp = Project(slug: slug("kirikakaese/SMP"), repositoryID: 1001, addedAt: now - 30 * day)
        let evac = Project(slug: slug("kirikakaese/EVAC-BETA"), repositoryID: 1002, addedAt: now - 20 * day)
        let dial = Project(slug: slug("kirikakaese/DIAL-BETA"), repositoryID: 1003, addedAt: now - 10 * day)
        let metadata = InMemoryMetadataStore(projects: [smp, evac, dial])
        for record in demoHistory(for: smp, now: now) {
            try? metadata.saveDropRecord(record)
        }
        demoRegistries(metadata, for: smp)

        let secrets = InMemorySecretStore()
        let token: OAuthToken? = switch account {
        case .signedIn: OAuthToken(accessToken: "demo", scopes: ["repo"])
        case .signedOut: nil
        case .sessionEnded:
            OAuthToken(
                accessToken: "demo", accessTokenExpiresIn: -60, refreshToken: "demo", refreshTokenExpiresIn: -60
            )
        }
        if let token, let data = try? JSONEncoder().encode(TokenSet(token, issuedAt: now)) {
            try? secrets.setData(data, for: AuthService.keychainAccount)
        }

        let github = InMemoryGitHubService(
            user: GitHubUser(id: 252_577_764, login: "kirikakaese", name: "Kiri"),
            repositories: [
                GitHubRepository(
                    id: 1001, fullName: "kirikakaese/SMP", defaultBranch: "main",
                    summary: "SSH Management Platform: a native macOS app for SSH keys and hosts.",
                    pushedAt: now - day
                ),
                GitHubRepository(id: 1002, fullName: "kirikakaese/EVAC-BETA", pushedAt: now - 3 * day),
                GitHubRepository(id: 1003, fullName: "kirikakaese/DIAL-BETA", isPrivate: true, pushedAt: now - 5 * day),
                GitHubRepository(id: 1004, fullName: "kirikakaese/scoop-bucket", pushedAt: now - 4 * day),
            ]
        )
        return ServiceContainer(
            metadata: metadata,
            auth: AuthService(endpoint: DemoOAuthEndpoint(), secrets: secrets),
            github: github,
            releases: InMemoryReleaseService(releases: demoReleases(now: now)),
            repository: demoRepository(),
            actions: demoActions(now: now),
            notifier: RecordingDropNotifier()
        )
    }

    /// DROP publishes SMP's Scoop manifest; release.yml keeps the Homebrew tap.
    private static func demoRegistries(_ metadata: any MetadataStoring, for project: Project) {
        let setting = DestinationSetting(destination: .scoopBucket, mode: .managed)
        try? metadata.saveDestinationSetting(setting, projectID: project.id)
        let setup = RegistrySetup(
            destination: .scoopBucket,
            repository: "kirikakaese/scoop-bucket",
            path: "bucket/smp.json",
            assetPattern: "SMP-*.zip"
        )
        try? metadata.saveRegistrySetup(setup, projectID: project.id)
    }

    private static func slug(_ text: String) -> RepositorySlug {
        guard let slug = RepositorySlug(parsing: text) else { preconditionFailure("Invalid demo slug \(text)") }
        return slug
    }

    private static func demoReleases(now: Date) -> [GitHubRelease] {
        let day: TimeInterval = 86_400
        func assets(_ version: String, from id: Int64) -> [GitHubAsset] {
            func digest(_ name: String) -> String { "sha256:" + Checksums.sha256(of: Data(name.utf8)) }
            return [
                GitHubAsset(id: id, name: "SMP-\(version).dmg", size: 8_412_331, digest: digest("dmg\(version)")),
                GitHubAsset(id: id + 1, name: "SMP-\(version).zip", size: 7_903_112, digest: digest("zip\(version)")),
                GitHubAsset(id: id + 2, name: "SHA256SUMS.txt", size: 168, digest: digest("sums\(version)")),
            ]
        }
        return [
            GitHubRelease(
                id: 4, tagName: "v1.0.0-beta.1", name: "SMP 1.0.0 Beta 1", isPrerelease: true,
                htmlURL: URL(string: "https://github.com/kirikakaese/SMP/releases"), publishedAt: now - day,
                assets: assets("1.0.0-beta.1", from: 40)
            ),
            GitHubRelease(
                id: 3, tagName: "v0.9.2", name: "SMP 0.9.2",
                htmlURL: URL(string: "https://github.com/kirikakaese/SMP/releases"), publishedAt: now - 4 * day,
                assets: assets("0.9.2", from: 30)
            ),
            GitHubRelease(
                id: 2, tagName: "v0.9.1", name: "SMP 0.9.1",
                htmlURL: URL(string: "https://github.com/kirikakaese/SMP/releases"), publishedAt: now - 9 * day,
                assets: assets("0.9.1", from: 20)
            ),
            GitHubRelease(
                id: 1, tagName: "v0.9.0", name: "SMP 0.9.0",
                htmlURL: URL(string: "https://github.com/kirikakaese/SMP/releases"), publishedAt: now - 14 * day,
                assets: assets("0.9.0", from: 10)
            ),
        ]
    }

    /// SMP's history since 0.9.2: the commits the next drop's notes are written from.
    private static func demoRepository() -> InMemoryRepositoryService {
        let messages = [
            "feat(ui): add an app icon and let people choose another key (#21)",
            "fix(agent): ask once after sleep instead of twice (#23)",
            "feat(keys)!: store key metadata in the new library format (#24)",
            "feat(hosts): connect to a host from the menu bar (#25)",
            "chore: update actions/checkout to v5 (#20)",
            "perf(library): load large ~/.ssh folders without blocking (#26)",
        ]
        var commits = [GitHubCommit(sha: "0920000", message: "fix: 0.9.2 (#19)")]
        commits += messages.enumerated().map { GitHubCommit(sha: "c0ffee\($0.offset)", message: $0.element) }
        return InMemoryRepositoryService(
            commits: commits,
            tags: ["v0.9.2": "0920000", "v0.9.1": "0910000", "v0.9.0": "0900000"],
            files: [
                "CHANGELOG.md": "# Changelog\n",
                ".github/workflows/ci.yml": "on:\n  push:\n    branches: [main]\n  pull_request:\n",
                ".github/workflows/release.yml": """
                    on:
                      push:
                        tags: ['v*']
                    jobs:
                      tap:
                        steps:
                          - run: git clone https://github.com/kirikakaese/homebrew-tap.git tap
                    """,
                ".github/workflows/strings.yml": "on:\n  workflow_dispatch:\n  pull_request:\n",
                // The Scoop bucket's manifest (the demo keeps every repository's files together).
                "bucket/smp.json": """
                    {
                        "version": "0.9.2",
                        "description": "SSH Management Platform",
                        "homepage": "https://github.com/kirikakaese/SMP",
                        "license": "GPL-3.0-only",
                        "url": "https://github.com/kirikakaese/SMP/releases/download/v0.9.2/SMP-0.9.2.zip",
                        "hash": "\(Checksums.sha256(of: Data("zip0.9.2".utf8)))",
                        "bin": "smp.exe"
                    }

                    """,
            ]
        )
    }

    /// SMP's workflows and a few runs, one of them still building.
    private static func demoActions(now: Date) -> InMemoryActionsService {
        var state = InMemoryActionsService.State()
        state.workflows = [
            GitHubWorkflow(id: 1, name: "CI", path: ".github/workflows/ci.yml"),
            GitHubWorkflow(id: 2, name: "Release", path: ".github/workflows/release.yml"),
            GitHubWorkflow(id: 3, name: "Strings", path: ".github/workflows/strings.yml"),
        ]
        let url = URL(string: "https://github.com/kirikakaese/SMP/actions")
        state.runs = [
            GitHubWorkflowRun(
                id: 103, workflowID: 2, name: "Release", title: "v1.0.0-beta.1", headBranch: "v1.0.0-beta.1",
                event: "push", status: "in_progress", conclusion: nil, runNumber: 14, htmlURL: url, createdAt: now - 300
            ),
            GitHubWorkflowRun(
                id: 102, workflowID: 1, name: "CI", title: "Bring the README up to date for the 0.9 beta",
                status: "completed", conclusion: "success", runNumber: 88, htmlURL: url, createdAt: now - 3_600
            ),
            GitHubWorkflowRun(
                id: 101, workflowID: 1, name: "CI", title: "Add an app icon", status: "completed",
                conclusion: "failure", runNumber: 87, htmlURL: url, createdAt: now - 7_200
            ),
        ]
        state.jobs[103] = [
            GitHubJob(id: 1031, name: "Build, sign and publish", status: "in_progress", conclusion: nil, steps: [
                GitHubJob.Step(number: 1, name: "Set up job", status: "completed", conclusion: "success"),
                GitHubJob.Step(number: 2, name: "Build universal app", status: "completed", conclusion: "success"),
                GitHubJob.Step(number: 3, name: "Sign the update", status: "in_progress", conclusion: nil),
            ]),
        ]
        state.logs[1031] = """
            ** BUILD SUCCEEDED **
            All code in build/SMP.app is ad-hoc signed without the Hardened Runtime.
            SMP started and kept running for 15 seconds.
            Signing SMP-1.0.0-beta.1.zip with the update key…
            """
        state.artifacts[102] = [GitHubArtifact(id: 501, name: "SMP-build", size: 8_412_331)]
        return InMemoryActionsService(state)
    }

    private static func demoHistory(for project: Project, now: Date) -> [DropRecord] {
        let day: TimeInterval = 86_400
        return [
            DropRecord(
                projectID: project.id, tagName: "v1.0.0-beta.1", isDraft: false, isPrerelease: true,
                startedAt: now - day, finishedAt: now - day + 40, outcome: .dropped
            ),
            DropRecord(
                projectID: project.id, tagName: "v0.9.2", isDraft: false, isPrerelease: false,
                startedAt: now - 4 * day, finishedAt: now - 4 * day + 50, outcome: .dropped
            ),
            DropRecord(
                projectID: project.id, tagName: "v0.9.1", isDraft: false, isPrerelease: false,
                startedAt: now - 9 * day - 600, finishedAt: now - 9 * day - 560, outcome: .failed,
                failedStep: "Upload SMP-0.9.1.dmg"
            ),
        ]
    }
}

/// Shows a sign-in code and then waits forever: enough for a screenshot of the sign-in sheet.
private struct DemoOAuthEndpoint: OAuthEndpoint {
    func requestDeviceCode(scopes: [String]) async throws -> DeviceAuthorization {
        guard let url = URL(string: "https://github.com/login/device") else { throw DROPError.somethingWentWrong }
        return DeviceAuthorization(
            deviceCode: "demo", userCode: "WDJB-MJHT", verificationURL: url, expiresIn: 900, interval: 5
        )
    }

    func pollForToken(deviceCode: String) async throws -> DevicePollResult { .pending }

    func refresh(refreshToken: String) async throws -> OAuthToken { throw DROPError.sessionExpired }
}

#endif
