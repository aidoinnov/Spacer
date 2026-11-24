/// The sole builder accumulates one directory's file deltas until a publication
/// boundary. No tree is owned here; flushing remains the builder's job.
@frozen public struct ObservedByteBatch {
    @inlinable public init() {}
    @frozen public struct Delta {
        public let parent: Int
        public let logical: Int64
        public let allocated: Int64
        @usableFromInline init(parent: Int, logical: Int64, allocated: Int64) {
            self.parent = parent; self.logical = logical; self.allocated = allocated
        }
    }
    @usableFromInline var parent: Int?
    @usableFromInline var logical: Int64 = 0
    @usableFromInline var allocated: Int64 = 0

    @inlinable public mutating func add(parent: Int, logical: Int64, allocated: Int64) {
        precondition(self.parent == nil || self.parent == parent)
        self.parent = parent
        self.logical += logical
        self.allocated += allocated
    }

    @inlinable public mutating func drain() -> Delta? {
        guard let parent else { return nil }
        let delta = Delta(parent: parent, logical: logical, allocated: allocated)
        self.parent = nil; logical = 0; allocated = 0
        return delta
    }
}
