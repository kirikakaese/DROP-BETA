import Foundation

/// A GitHub repository added to DROP.
public struct Project: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    /// The repository's current name. Updated when GitHub reports that it was renamed.
    public var slug: RepositorySlug
    public let addedAt: Date

    public init(id: UUID = UUID(), slug: RepositorySlug, addedAt: Date = Date()) {
        self.id = id
        self.slug = slug
        self.addedAt = addedAt
    }
}
