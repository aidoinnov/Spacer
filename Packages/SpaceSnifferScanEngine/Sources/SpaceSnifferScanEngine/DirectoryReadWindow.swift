/// Builder-owned bounded results. Completion never releases a slot: only
/// consumption does. OS adapters supply plans; this loop owns refill/dedup.
@frozen public struct DirectoryReadWindow<Key: Hashable, Output: Sendable> {
    public let futureCapacity: Int
    @usableFromInline var tickets: [Key: DirectoryReadTicket<Output>] = [:]
    @inlinable public init(futureCapacity: Int) {
        precondition(futureCapacity >= 0); self.futureCapacity = futureCapacity
    }
    @inlinable public var count: Int { tickets.count }
    @inlinable public var isEmpty: Bool { tickets.isEmpty }
    @inlinable public var values: Dictionary<Key, DirectoryReadTicket<Output>>.Values { tickets.values }
    @inlinable public mutating func take(for key: Key) -> DirectoryReadTicket<Output>? {
        tickets.removeValue(forKey: key)
    }
    /// Both retained results and examined plans are bounded. The default work
    /// limit is futureCapacity; callers may explicitly budget more duplicate/
    /// ineligible plans. A rejected submit does not allow an unbounded walk.
    @inlinable public mutating func replenish<Plans: Sequence>(from plans: Plans,
        maximumPlans: Int? = nil,
        key: (Plans.Element) -> Key, submit: (Plans.Element) -> DirectoryReadTicket<Output>?) {
        let limit = maximumPlans ?? futureCapacity
        precondition(limit >= 0)
        guard tickets.count < futureCapacity, limit > 0 else { return }
        var iterator = plans.makeIterator()
        var examined = 0
        while tickets.count < futureCapacity, examined < limit, let plan = iterator.next() {
            examined += 1
            let id = key(plan)
            guard tickets[id] == nil else { continue }
            if let ticket = submit(plan) { tickets[id] = ticket }
        }
    }
    public mutating func removeAll() { tickets.removeAll() }
}
