import DROPCore
import Foundation

/// Sample data shared by the test targets.
public enum Fixtures {
    /// A fixed point in time with whole seconds, so dates survive a round trip through SQLite.
    public static let referenceDate = Date(timeIntervalSince1970: 1_790_000_000)

    public static func slug(_ text: String) -> RepositorySlug {
        guard let slug = RepositorySlug(parsing: text) else {
            preconditionFailure("Invalid fixture slug \(text)")
        }
        return slug
    }

    public static func project(_ text: String, addedSecondsLater seconds: TimeInterval = 0) -> Project {
        Project(slug: slug(text), addedAt: referenceDate.addingTimeInterval(seconds))
    }
}
