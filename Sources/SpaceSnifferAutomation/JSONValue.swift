import Foundation

public enum JSONValue: Codable, Sendable, Equatable {
    case null, bool(Bool), integer(Int64), number(Double), string(String), array([JSONValue]), object([String: JSONValue])
    public init(from decoder: Decoder) throws {
        let c = try decoder.singleValueContainer()
        if c.decodeNil() { self = .null }
        else if let v = try? c.decode(Bool.self) { self = .bool(v) }
        else if let v = try? c.decode(Int64.self) { self = .integer(v) }
        else if let v = try? c.decode(Double.self) { self = .number(v) }
        else if let v = try? c.decode(String.self) { self = .string(v) }
        else if let v = try? c.decode([String: JSONValue].self) { self = .object(v) }
        else { self = .array(try c.decode([JSONValue].self)) }
    }
    public func encode(to encoder: Encoder) throws {
        var c = encoder.singleValueContainer()
        switch self {
        case .null: try c.encodeNil()
        case .bool(let v): try c.encode(v)
        case .integer(let v): try c.encode(v)
        case .number(let v): try c.encode(v)
        case .string(let v): try c.encode(v)
        case .array(let v): try c.encode(v)
        case .object(let v): try c.encode(v)
        }
    }
    public static func int(_ value: Int) -> Self { .integer(Int64(value)) }
    public static func date(_ date: Date?) -> Self { date.map { .number($0.timeIntervalSince1970) } ?? .null }
    public var string: String? { if case .string(let value) = self { value } else { nil } }
    public var integer: Int? { if case .integer(let value) = self { Int(exactly: value) } else { nil } }
    public var boolean: Bool? { if case .bool(let value) = self { value } else { nil } }
    public var object: [String: JSONValue]? { if case .object(let value) = self { value } else { nil } }
}
public struct ControlRequest: Codable, Sendable {
    public let id: JSONValue
    public let token: String
    public let command: String
    public let arguments: [String: JSONValue]
    public init(id: JSONValue, token: String, command: String, arguments: [String: JSONValue] = [:]) {
        self.id = id; self.token = token; self.command = command; self.arguments = arguments
    }
}
public struct ControlError: Error, Codable, Sendable, LocalizedError {
    public let code: String
    public let message: String
    public init(_ code: String, _ message: String) { self.code = code; self.message = message }
    public var errorDescription: String? { message }
}
public struct ControlResponse: Codable, Sendable {
    public let id: JSONValue
    public let result: JSONValue?
    public let error: ControlError?
    public init(id: JSONValue, result: JSONValue? = nil, error: ControlError? = nil) { self.id = id; self.result = result; self.error = error }
}
public extension Dictionary where Key == String, Value == JSONValue {
    func requiredString(_ key: String) throws -> String {
        guard let v = self[key]?.string, !v.isEmpty else { throw ControlError("invalid_argument", "\(key) must be a non-empty string") }; return v
    }
    func boundedInt(_ key: String, default fallback: Int, range: ClosedRange<Int>) throws -> Int {
        guard let raw = self[key] else { return fallback }
        guard let v = raw.integer, range.contains(v) else { throw ControlError("invalid_argument", "\(key) must be an integer in \(range)") }; return v
    }
}
