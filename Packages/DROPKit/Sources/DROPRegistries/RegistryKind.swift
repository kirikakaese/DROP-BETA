import Foundation

/// The package registries DROP can publish to.
public enum RegistryKind: String, CaseIterable, Identifiable, Sendable, Codable {
    case homebrewTap
    case scoopBucket
    case ghcr
    case npm

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .homebrewTap: String(localized: "Homebrew Tap")
        case .scoopBucket: String(localized: "Scoop Bucket")
        case .ghcr: String(localized: "GitHub Container Registry")
        case .npm: String(localized: "npm")
        }
    }

    public var systemImage: String {
        switch self {
        case .homebrewTap: "mug"
        case .scoopBucket: "takeoutbag.and.cup.and.straw"
        case .ghcr: "shippingbox"
        case .npm: "cube"
        }
    }
}
