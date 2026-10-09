import DROPCore
import Foundation

/// The signed-in account (`GET /user`).
public struct GitHubUser: Decodable, Sendable, Equatable {
    public let id: Int64
    public let login: String
    public let name: String?
    public let avatarURL: URL?

    public init(id: Int64, login: String, name: String? = nil, avatarURL: URL? = nil) {
        self.id = id
        self.login = login
        self.name = name
        self.avatarURL = avatarURL
    }

    enum CodingKeys: String, CodingKey {
        case id, login, name
        case avatarURL = "avatar_url"
    }
}

/// A repository as GitHub describes it (`GET /repos/{owner}/{repo}`, `GET /user/repos`).
public struct GitHubRepository: Decodable, Sendable, Equatable, Identifiable {
    public let id: Int64
    /// `owner/name` as GitHub spells it now.
    public let fullName: String
    public let isPrivate: Bool
    public let isArchived: Bool
    public let defaultBranch: String
    public let summary: String?
    public let pushedAt: Date?

    public init(
        id: Int64,
        fullName: String,
        isPrivate: Bool = false,
        isArchived: Bool = false,
        defaultBranch: String = "main",
        summary: String? = nil,
        pushedAt: Date? = nil
    ) {
        self.id = id
        self.fullName = fullName
        self.isPrivate = isPrivate
        self.isArchived = isArchived
        self.defaultBranch = defaultBranch
        self.summary = summary
        self.pushedAt = pushedAt
    }

    public var slug: RepositorySlug? { RepositorySlug(parsing: fullName) }

    enum CodingKeys: String, CodingKey {
        case id
        case fullName = "full_name"
        case isPrivate = "private"
        case isArchived = "archived"
        case defaultBranch = "default_branch"
        case summary = "description"
        case pushedAt = "pushed_at"
    }
}

extension GitHubRequest {
    /// `GET /user`.
    public static var currentUser: GitHubRequest { GitHubRequest(path: "/user") }

    /// `GET /repositories/{id}`: finds a repository by ID, whatever it is called now.
    public static func repository(id: Int64) -> GitHubRequest {
        GitHubRequest(path: "/repositories/\(id)")
    }

    /// `GET /user/repos`: repositories you own or collaborate on, most recently pushed first.
    public static var yourRepositories: GitHubRequest {
        GitHubRequest(path: "/user/repos", query: [
            URLQueryItem(name: "per_page", value: "100"),
            URLQueryItem(name: "sort", value: "pushed"),
        ])
    }
}
