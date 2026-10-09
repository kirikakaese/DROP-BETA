import DROPCore
import DROPPersistence
import Foundation

/// The set of services the app runs with. Views and view models receive it by injection,
/// so tests and previews can swap in fakes.
public struct ServiceContainer: Sendable {
    public var metadata: any MetadataStoring
    /// Set when a service could not start normally (for example, the metadata store could not be
    /// opened and an in-memory store is used instead). Shown to the user.
    public var startupIssue: DROPError?

    public init(metadata: any MetadataStoring, startupIssue: DROPError? = nil) {
        self.metadata = metadata
        self.startupIssue = startupIssue
    }

    /// The services the app runs with.
    public static func live() -> ServiceContainer {
        do {
            return ServiceContainer(metadata: try GRDBMetadataStore.live())
        } catch {
            Log.persistence.error("Could not open the metadata store: \(error.localizedDescription, privacy: .public)")
            return ServiceContainer(
                metadata: InMemoryMetadataStore(),
                startupIssue: .storageUnavailable(details: error.localizedDescription)
            )
        }
    }

    /// In-memory services for previews and tests. Never touches disk or the network.
    public static func preview(projects: [Project] = []) -> ServiceContainer {
        ServiceContainer(metadata: InMemoryMetadataStore(projects: projects))
    }
}
