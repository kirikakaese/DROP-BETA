import CryptoKit
import Foundation

/// SHA-256 checksums of release assets and the `SHA256SUMS.txt` file that lists them.
public enum Checksums {
    public static let fileName = "SHA256SUMS.txt"

    /// The SHA-256 of a file as lowercase hex, read in chunks so large assets don't fill memory.
    public static func sha256(of url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
            hasher.update(data: chunk)
        }
        return hex(hasher.finalize())
    }

    public static func sha256(of data: Data) -> String {
        hex(SHA256.hash(data: data))
    }

    /// The contents of `SHA256SUMS.txt` in the format `shasum -a 256` writes and `shasum -c`
    /// reads: `<hex>  <name>`, one line per asset, sorted by name.
    public static func sumsFile(_ checksums: [String: String]) -> String {
        checksums.sorted { $0.key < $1.key }
            .map { "\($0.value)  \($0.key)\n" }
            .joined()
    }

    private static func hex(_ digest: SHA256.Digest) -> String {
        digest.map { String(format: "%02x", $0) }.joined()
    }
}
