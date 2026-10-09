import Foundation

/// Checks tag names against git's rules for ref names (`git check-ref-format`), so a drop never
/// fails halfway because GitHub refuses the tag.
public enum TagName {
    public static func isValid(_ name: String) -> Bool {
        guard !name.isEmpty, name.count <= 200, name != "@",
            !name.hasPrefix("-"), !name.hasPrefix("/"), !name.hasSuffix("/"),
            !name.hasSuffix("."), !name.hasSuffix(".lock"),
            !name.contains(".."), !name.contains("//"), !name.contains("@{")
        else { return false }
        let forbidden = Set(" ~^:?*[\\")
        guard !name.contains(where: { forbidden.contains($0) }) else { return false }
        guard name.unicodeScalars.allSatisfy({ $0.value > 0x20 && $0.value != 0x7F }) else { return false }
        return name.split(separator: "/").allSatisfy { !$0.hasPrefix(".") }
    }
}
