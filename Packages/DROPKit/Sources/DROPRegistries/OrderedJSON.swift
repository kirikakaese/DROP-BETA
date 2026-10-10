import Foundation

/// JSON that keeps the order of object keys, so updating a Scoop manifest changes only the values
/// DROP sets. Numbers keep their original spelling.
public indirect enum OrderedJSON: Equatable, Sendable {
    public struct Member: Equatable, Sendable {
        public var key: String
        public var value: OrderedJSON

        public init(_ key: String, _ value: OrderedJSON) {
            self.key = key
            self.value = value
        }
    }

    case object([Member])
    case array([OrderedJSON])
    case string(String)
    case number(String)
    case bool(Bool)
    case null

    public struct ParseError: Error, Equatable {
        public let offset: Int
    }

    public init(parsing text: String) throws {
        var parser = Parser(scalars: Array(text.unicodeScalars))
        self = try parser.document()
    }

    public subscript(key: String) -> OrderedJSON? {
        get {
            guard case .object(let members) = self else { return nil }
            return members.first { $0.key == key }?.value
        }
        set {
            guard case .object(var members) = self else { return }
            if let index = members.firstIndex(where: { $0.key == key }) {
                if let newValue {
                    members[index].value = newValue
                } else {
                    members.remove(at: index)
                }
            } else if let newValue {
                members.append(Member(key, newValue))
            }
            self = .object(members)
        }
    }

    public var stringValue: String? {
        if case .string(let value) = self { value } else { nil }
    }

    /// Indented with four spaces, one value per line, like the manifests in Scoop buckets.
    public func formatted() -> String {
        var output = ""
        write(to: &output, indent: 0)
        return output + "\n"
    }

    private func write(to output: inout String, indent: Int) {
        let inner = String(repeating: " ", count: (indent + 1) * 4)
        let closing = String(repeating: " ", count: indent * 4)
        switch self {
        case .object(let members) where members.isEmpty:
            output += "{}"
        case .object(let members):
            output += "{\n"
            for (index, member) in members.enumerated() {
                output += inner + Self.quoted(member.key) + ": "
                member.value.write(to: &output, indent: indent + 1)
                output += index == members.count - 1 ? "\n" : ",\n"
            }
            output += closing + "}"
        case .array(let values) where values.isEmpty:
            output += "[]"
        case .array(let values):
            output += "[\n"
            for (index, value) in values.enumerated() {
                output += inner
                value.write(to: &output, indent: indent + 1)
                output += index == values.count - 1 ? "\n" : ",\n"
            }
            output += closing + "]"
        case .string(let value):
            output += Self.quoted(value)
        case .number(let value):
            output += value
        case .bool(let value):
            output += value ? "true" : "false"
        case .null:
            output += "null"
        }
    }

    static func quoted(_ text: String) -> String {
        var output = "\""
        for scalar in text.unicodeScalars {
            switch scalar {
            case "\"": output += "\\\""
            case "\\": output += "\\\\"
            case "\n": output += "\\n"
            case "\r": output += "\\r"
            case "\t": output += "\\t"
            case let control where control.value < 0x20:
                output += String(format: "\\u%04x", control.value)
            default: output.unicodeScalars.append(scalar)
            }
        }
        return output + "\""
    }
}

private struct Parser {
    static let whitespace: Set<Unicode.Scalar> = [" ", "\n", "\r", "\t"]
    static let numberCharacters = Set("+-0123456789.eE".unicodeScalars)

    let scalars: [Unicode.Scalar]
    var position = 0

    init(scalars: [Unicode.Scalar]) {
        self.scalars = scalars
    }

    mutating func document() throws -> OrderedJSON {
        let value = try self.value()
        skipWhitespace()
        guard position == scalars.count else { throw failure }
        return value
    }

    private var failure: OrderedJSON.ParseError { OrderedJSON.ParseError(offset: position) }

    private mutating func value() throws -> OrderedJSON {
        skipWhitespace()
        guard position < scalars.count else { throw failure }
        switch scalars[position] {
        case "{": return try object()
        case "[": return try array()
        case "\"": return .string(try string())
        case "t":
            try literal("true")
            return .bool(true)
        case "f":
            try literal("false")
            return .bool(false)
        case "n":
            try literal("null")
            return .null
        default:
            return .number(try number())
        }
    }

    private mutating func object() throws -> OrderedJSON {
        position += 1
        var members: [OrderedJSON.Member] = []
        skipWhitespace()
        if peek == "}" {
            position += 1
            return .object(members)
        }
        while true {
            skipWhitespace()
            guard peek == "\"" else { throw failure }
            let key = try string()
            skipWhitespace()
            guard peek == ":" else { throw failure }
            position += 1
            members.append(OrderedJSON.Member(key, try value()))
            skipWhitespace()
            switch peek {
            case ",":
                position += 1
            case "}":
                position += 1
                return .object(members)
            default:
                throw failure
            }
        }
    }

    private mutating func array() throws -> OrderedJSON {
        position += 1
        var values: [OrderedJSON] = []
        skipWhitespace()
        if peek == "]" {
            position += 1
            return .array(values)
        }
        while true {
            values.append(try value())
            skipWhitespace()
            switch peek {
            case ",":
                position += 1
            case "]":
                position += 1
                return .array(values)
            default:
                throw failure
            }
        }
    }

    private mutating func string() throws -> String {
        position += 1
        var result = String.UnicodeScalarView()
        while position < scalars.count {
            let scalar = scalars[position]
            position += 1
            switch scalar {
            case "\"":
                return String(result)
            case "\\":
                result.append(try escaped())
            default:
                result.append(scalar)
            }
        }
        throw failure
    }

    private mutating func escaped() throws -> Unicode.Scalar {
        guard position < scalars.count else { throw failure }
        let scalar = scalars[position]
        position += 1
        switch scalar {
        case "\"", "\\", "/": return scalar
        case "b": return "\u{08}"
        case "f": return "\u{0C}"
        case "n": return "\n"
        case "r": return "\r"
        case "t": return "\t"
        case "u":
            let high = try hex4()
            if (0xD800...0xDBFF).contains(high) {
                guard peek == "\\", position + 1 < scalars.count, scalars[position + 1] == "u" else { throw failure }
                position += 2
                let low = try hex4()
                guard (0xDC00...0xDFFF).contains(low),
                    let combined = Unicode.Scalar(0x10000 + ((high - 0xD800) << 10) + (low - 0xDC00))
                else { throw failure }
                return combined
            }
            guard let single = Unicode.Scalar(high) else { throw failure }
            return single
        default:
            throw failure
        }
    }

    private mutating func hex4() throws -> UInt32 {
        guard position + 4 <= scalars.count else { throw failure }
        let digits = String(String.UnicodeScalarView(scalars[position..<position + 4]))
        guard let value = UInt32(digits, radix: 16) else { throw failure }
        position += 4
        return value
    }

    private mutating func number() throws -> String {
        let start = position
        while position < scalars.count, Self.numberCharacters.contains(scalars[position]) {
            position += 1
        }
        let text = String(String.UnicodeScalarView(scalars[start..<position]))
        guard !text.isEmpty, Double(text) != nil else { throw failure }
        return text
    }

    private mutating func literal(_ word: String) throws {
        let expected = Array(word.unicodeScalars)
        guard position + expected.count <= scalars.count,
            Array(scalars[position..<position + expected.count]) == expected
        else { throw failure }
        position += expected.count
    }

    private var peek: Unicode.Scalar? {
        position < scalars.count ? scalars[position] : nil
    }

    private mutating func skipWhitespace() {
        while position < scalars.count, Self.whitespace.contains(scalars[position]) {
            position += 1
        }
    }
}
