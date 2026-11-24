/// OS adapters own file queries, names, metadata, native errors and handles.
/// The shared scheduler accepts complete immutable batches, never an OS handle.
public protocol DirectoryBatchReader: Sendable {
    associatedtype Output: Sendable
    func readDirectory(at path: String, control: ScanControl) -> Output
}

@frozen public struct DirectoryEntry<Metadata: Sendable>: Sendable {
    public let name: String
    public let values: Metadata?
    public let directoryEntryCount: UInt32?
    @inlinable public init(name: String, values: Metadata?, directoryEntryCount: UInt32?) {
        self.name = name; self.values = values; self.directoryEntryCount = directoryEntryCount
    }
}

@frozen public struct DirectoryListing<Metadata: Sendable>: Sendable {
    public let names: [String]
    public let entries: [DirectoryEntry<Metadata>]?
    @inlinable public init(names: [String], entries: [DirectoryEntry<Metadata>]?) {
        self.names = names; self.entries = entries
    }
}

public struct DirectoryReadOutput<Listing: Sendable, Statistics: Sendable>: Sendable {
    public enum Value: Sendable {
        case listing(Listing)
        case failure(domain: String, code: Int)
        case retryInline
        case cancelled
    }
    public let value: Value
    public let statistics: Statistics
    public init(value: Value, statistics: Statistics) { self.value = value; self.statistics = statistics }
}
