/// Scheduling is shared; admission thresholds are supplied by each platform's
/// measured policy. Neither native metadata types nor OS queries belong here.
@frozen public struct DirectoryReadWindowPolicy: Sendable {
    public let concurrency: Int
    public let minimumSiblingCount: Int
    public let admitUnknownEntryCount: Bool
    public let admittedEntryRange: ClosedRange<UInt32>
    public init(concurrency: Int, minimumSiblingCount: Int, admittedEntryRange: ClosedRange<UInt32>, admitUnknownEntryCount: Bool = false) {
        precondition(concurrency > 0 && minimumSiblingCount > 1)
        self.concurrency = concurrency; self.minimumSiblingCount = minimumSiblingCount
        self.admittedEntryRange = admittedEntryRange; self.admitUnknownEntryCount = admitUnknownEntryCount
    }
    @inlinable public var futureCapacity: Int { concurrency - 1 }
    @inlinable public func hasVacancy(outstanding: Int, pending: Int) -> Bool {
        concurrency > 1 && outstanding < futureCapacity && pending > 1
    }
    @inlinable public func admits(entryCount: UInt32?) -> Bool {
        entryCount.map { admittedEntryRange.contains($0) } ?? admitUnknownEntryCount
    }
}
