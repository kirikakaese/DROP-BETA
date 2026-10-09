import Foundation

/// A GitHub repository added to DROP.
public struct Project: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    /// The repository's current name. Updated when GitHub reports that it was renamed.
    public var slug: RepositorySlug
    /// GitHub's ID for the repository. Stays the same when the repository is renamed or moved.
    public var repositoryID: Int64?
    public let addedAt: Date

    public init(id: UUID = UUID(), slug: RepositorySlug, repositoryID: Int64? = nil, addedAt: Date = Date()) {
        self.id = id
        self.slug = slug
        self.repositoryID = repositoryID
        self.addedAt = addedAt
    }
}
