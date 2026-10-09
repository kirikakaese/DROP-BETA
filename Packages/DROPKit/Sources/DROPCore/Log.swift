import os

/// Unified-logging categories.
///
/// Rules: never log tokens, codes or anything else secret. Interpolate repository names and user
/// names with `privacy: .private` so they are redacted in collected logs.
public enum Log {
    public static let subsystem = "com.kirikakaese.drop"

    public static let app = Logger(subsystem: subsystem, category: "app")
    public static let persistence = Logger(subsystem: subsystem, category: "persistence")
    public static let network = Logger(subsystem: subsystem, category: "network")
    public static let keychain = Logger(subsystem: subsystem, category: "keychain")
}
