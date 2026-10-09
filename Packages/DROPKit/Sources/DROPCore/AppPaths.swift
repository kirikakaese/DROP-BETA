import Foundation

/// Where DROP keeps its files.
public enum AppPaths {
    /// `~/Library/Application Support/DROP`, created with mode 0700 if it doesn't exist.
    public static func applicationSupportDirectory() throws -> URL {
        let base = try FileManager.default.url(
            for: .applicationSupportDirectory, in: .userDomainMask, appropriateFor: nil, create: true
        )
        let directory = base.appending(path: "DROP", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(
            at: directory, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700]
        )
        return directory
    }
}
