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
    /// Set when a service could not start normally (for example, the metadata store could not be
    /// opened and an in-memory store is used instead). Shown to the user.
    public var startupIssue: DROPError?

    public init(
        metadata: any MetadataStoring,
        auth: any AuthServicing,
        github: any GitHubServicing,
        startupIssue: DROPError? = nil
    ) {
        self.metadata = metadata
        self.auth = auth
        self.github = github
        self.startupIssue = startupIssue
    }

    public var projects: ProjectService {
        ProjectService(github: github, metadata: metadata)
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
        let github = LiveGitHubService(client: GitHubClient(transport: transport, tokens: auth, userAgent: userAgent))
        do {
            return ServiceContainer(metadata: try GRDBMetadataStore.live(), auth: auth, github: github)
        } catch {
            Log.persistence.error("Could not open the metadata store: \(error.localizedDescription, privacy: .public)")
            return ServiceContainer(
                metadata: InMemoryMetadataStore(),
                auth: auth,
                github: github,
                startupIssue: .storageUnavailable(details: error.localizedDescription)
            )
        }
    }

    /// In-memory services for previews and tests. Never touches disk, the Keychain or the network.
    public static func preview(
        projects: [Project] = [],
        auth: (any AuthServicing)? = nil,
        github: (any GitHubServicing)? = nil
    ) -> ServiceContainer {
        ServiceContainer(
            metadata: InMemoryMetadataStore(projects: projects),
            auth: auth ?? AuthService(endpoint: nil, secrets: InMemorySecretStore()),
            github: github ?? InMemoryGitHubService()
        )
    }
}
