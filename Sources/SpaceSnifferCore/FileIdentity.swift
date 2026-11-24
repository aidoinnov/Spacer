import Foundation

/// Keeps native identity numeric until a legacy String consumer needs it.
/// The wrapped String API and its optional JSON field remain compatible.
@propertyWrapper
public struct FileIdentity: Codable, Hashable, Sendable {
    private enum Storage: Hashable, Sendable {
        case absent
        case native(device: Int64, inode: UInt64)
        case text(String)
    }
    private var storage: Storage
    var isPresent: Bool {
        if case .absent = storage { return false }
        return true
    }

    public var wrappedValue: String? {
        get {
            switch storage {
            case .absent: return nil
            case let .native(device, inode): return "\(device):\(inode)"
            case .text(let value): return value
            }
        }
        set { self = Self(wrappedValue: newValue) }
    }

    public init(wrappedValue: String? = nil) {
        guard let wrappedValue else { storage = .absent; return }
        let parts = wrappedValue.split(separator: ":", maxSplits: 1, omittingEmptySubsequences: false)
        if parts.count == 2, let device = Int64(parts[0]), let inode = UInt64(parts[1]),
           "\(device):\(inode)" == wrappedValue {
            storage = .native(device: device, inode: inode)
        } else {
            // Preserve arbitrary and noncanonical legacy identities byte for
            // byte, including leading zeros, plus signs and opaque text.
            storage = .text(wrappedValue)
        }
    }

    init(device: Int64, inode: UInt64) { storage = .native(device: device, inode: inode) }

    public init(from decoder: Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() { self.init(wrappedValue: nil) }
        else { self.init(wrappedValue: try container.decode(String.self)) }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        if let wrappedValue { try container.encode(wrappedValue) }
        else { try container.encodeNil() }
    }
}

// Synthesized Codable must retain Optional<String>'s absent-key behavior.
// Generic wrapper decoding alone would otherwise require the JSON key, and
// generic wrapper encoding would turn omitted nil into an explicit null.
extension KeyedDecodingContainer {
    public func decode(_ type: FileIdentity.Type, forKey key: Key) throws -> FileIdentity {
        FileIdentity(wrappedValue: try decodeIfPresent(String.self, forKey: key))
    }
}

extension KeyedEncodingContainer {
    public mutating func encode(_ value: FileIdentity, forKey key: Key) throws {
        try encodeIfPresent(value.wrappedValue, forKey: key)
    }
}
