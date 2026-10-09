#if DEBUG
import DROPCore
import DROPGitHub
import DROPPersistence
import Foundation

extension ServiceContainer {
    /// Services with sample data and a signed-in account, for the screenshots CI takes of pull
    /// requests. Debug builds only; never touches disk, the Keychain or the network.
    public static func demo(now: Date = Date()) -> ServiceContainer {
        let day: TimeInterval = 86_400
        let smp = Project(slug: slug("kirikakaese/SMP"), repositoryID: 1001, addedAt: now - 30 * day)
        let evac = Project(slug: slug("kirikakaese/EVAC-BETA"), repositoryID: 1002, addedAt: now - 20 * day)
        let dial = Project(slug: slug("kirikakaese/DIAL-BETA"), repositoryID: 1003, addedAt: now - 10 * day)
        let metadata = InMemoryMetadataStore(projects: [smp, evac, dial])
        for record in demoHistory(for: smp, now: now) {
            try? metadata.saveDropRecord(record)
        }

        let secrets = InMemorySecretStore()
        let tokens = TokenSet(OAuthToken(accessToken: "demo", scopes: ["repo"]), issuedAt: now)
        if let data = try? JSONEncoder().encode(tokens) {
            try? secrets.setData(data, for: AuthService.keychainAccount)
        }
        let endpoint = GitHubOAuthEndpoint(clientID: "demo", transport: OfflineTransport(), userAgent: "DROP")

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
            ]
        )
        return ServiceContainer(
            metadata: metadata,
            auth: AuthService(endpoint: endpoint, secrets: secrets),
            github: github,
            releases: InMemoryReleaseService(releases: demoReleases(now: now)),
            repository: demoRepository(),
            notifier: RecordingDropNotifier()
        )
    }

    private static func slug(_ text: String) -> RepositorySlug {
        guard let slug = RepositorySlug(parsing: text) else { preconditionFailure("Invalid demo slug \(text)") }
        return slug
    }

    private static func demoReleases(now: Date) -> [GitHubRelease] {
        let day: TimeInterval = 86_400
        func assets(_ version: String, from id: Int64) -> [GitHubAsset] {
            [
                GitHubAsset(id: id, name: "SMP-\(version).dmg", size: 8_412_331),
                GitHubAsset(id: id + 1, name: "SMP-\(version).zip", size: 7_903_112),
                GitHubAsset(id: id + 2, name: "SHA256SUMS.txt", size: 168),
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
            files: ["CHANGELOG.md": "# Changelog\n"]
        )
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

/// A transport that never connects. Demo services have nothing to send.
private struct OfflineTransport: HTTPTransport {
    func send(_ request: URLRequest) async throws -> (Data, HTTPURLResponse) {
        throw DROPError.network(details: "Demo mode is offline")
    }

    func upload(_ request: URLRequest, fromFile file: URL) async throws -> (Data, HTTPURLResponse) {
        throw DROPError.network(details: "Demo mode is offline")
    }
}
#endif
