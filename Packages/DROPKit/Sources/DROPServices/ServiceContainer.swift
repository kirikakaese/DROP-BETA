import DROPCore
import DROPGitHub
import DROPPersistence
import Foundation

/// The set of services the app runs with. Views and view models receive it by injection,
/// so tests and previews can swap in fakes.
public struct ServiceContainer: Sendable {
    public var metadata: any MetadataStoring
    public var auth: any AuthServicing
    public var github: any GitHubServicing
    public var releases: any ReleaseServicing
    public var repository: any RepositoryServicing
    public var actions: any ActionsServicing
    public var notifier: any DropNotifying
    /// Set when a service could not start normally (for example, the metadata store could not be
    /// opened and an in-memory store is used instead). Shown to the user.
    public var startupIssue: DROPError?

    public init(
        metadata: any MetadataStoring,
        auth: any AuthServicing,
        github: any GitHubServicing,
        releases: any ReleaseServicing,
        repository: any RepositoryServicing,
        actions: any ActionsServicing,
        notifier: any DropNotifying,
        startupIssue: DROPError? = nil
    ) {
        self.metadata = metadata
        self.auth = auth
        self.github = github
        self.releases = releases
        self.repository = repository
        self.actions = actions
        self.notifier = notifier
        self.startupIssue = startupIssue
    }

    public var projects: ProjectService {
        ProjectService(github: github, metadata: metadata)
    }

    public var changelog: ChangelogService {
        ChangelogService(repository: repository, github: github)
    }

    public var workflows: WorkflowService {
        WorkflowService(actions: actions, repository: repository, github: github)
    }

    public var drops: DropService {
        DropService(releases: releases, metadata: metadata, notifier: notifier, changelog: changelog)
    }

    /// The services the app runs with.
    public static func live(bundle: Bundle = .main) -> ServiceContainer {
        let version = bundle.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0"
        let userAgent = "DROP/\(version)"
        let transport = URLSessionTransport()
        let endpoint = OAuthConfiguration.clientID(in: bundle).map {
            GitHubOAuthEndpoint(clientID: $0, transport: transport, userAgent: userAgent)
        }
        let auth = AuthService(endpoint: endpoint, secrets: KeychainSecretStore(service: "\(Log.subsystem).github"))
        let client = GitHubClient(transport: transport, tokens: auth, userAgent: userAgent)
        let metadata: any MetadataStoring
        var startupIssue: DROPError?
        do {
            metadata = try GRDBMetadataStore.live()
        } catch {
            Log.persistence.error("Could not open the metadata store: \(error.localizedDescription, privacy: .public)")
            metadata = InMemoryMetadataStore()
            startupIssue = .storageUnavailable(details: error.localizedDescription)
        }
        return ServiceContainer(
            metadata: metadata,
            auth: auth,
            github: LiveGitHubService(client: client),
            releases: LiveReleaseService(client: client),
            repository: LiveRepositoryService(client: client),
            actions: LiveActionsService(client: client),
            notifier: UserNotificationDropNotifier(),
            startupIssue: startupIssue
        )
    }

    /// In-memory services for previews and tests. Never touches disk, the Keychain or the network.
    public static func preview(
        projects: [Project] = [],
        auth: (any AuthServicing)? = nil,
        github: (any GitHubServicing)? = nil,
        releases: (any ReleaseServicing)? = nil,
        repository: (any RepositoryServicing)? = nil,
        actions: (any ActionsServicing)? = nil,
        notifier: (any DropNotifying)? = nil
    ) -> ServiceContainer {
        ServiceContainer(
            metadata: InMemoryMetadataStore(projects: projects),
            auth: auth ?? AuthService(endpoint: nil, secrets: InMemorySecretStore()),
            github: github ?? InMemoryGitHubService(),
            releases: releases ?? InMemoryReleaseService(),
            repository: repository ?? InMemoryRepositoryService(),
            actions: actions ?? InMemoryActionsService(),
            notifier: notifier ?? RecordingDropNotifier()
        )
    }
}
