import DROPCore
import Foundation

/// Updates a Scoop manifest for a new version: `version`, and `url` and `hash` either at the top
/// level or for the one architecture the manifest lists. Everything else stays in its order.
public enum ScoopManifest {
    public static func bump(_ text: String, version: String, url: String, hash: String) throws -> String {
        var manifest: OrderedJSON
        do {
            manifest = try OrderedJSON(parsing: text)
        } catch {
            throw unsupported(String(localized: "It isn't valid JSON."))
        }
        guard manifest["version"]?.stringValue != nil else {
            throw unsupported(String(localized: "It has no version."))
        }
        manifest["version"] = .string(version)
        if manifest["url"] != nil {
            try set(url: url, hash: hash, in: &manifest)
        } else if case .object(let architectures)? = manifest["architecture"], architectures.count == 1,
            var entry = manifest["architecture"]?[architectures[0].key]
        {
            try set(url: url, hash: hash, in: &entry)
            manifest["architecture"]?[architectures[0].key] = entry
        } else {
            throw unsupported(String(localized: "It has one download per architecture, or none."))
        }
        return manifest.formatted()
    }

    private static func set(url: String, hash: String, in object: inout OrderedJSON) throws {
        guard object["url"]?.stringValue != nil, object["hash"]?.stringValue != nil else {
            throw unsupported(String(localized: "It downloads several files."))
        }
        object["url"] = .string(url)
        object["hash"] = .string(hash)
    }

    private static func unsupported(_ reason: String) -> DROPError {
        DROPError(
            .invalidArgument,
            whatHappened: String(localized: "DROP can't update this Scoop manifest. \(reason)"),
            howToFix: String(localized: "Update it by hand, or let the automation that maintains it keep doing so.")
        )
    }
}
