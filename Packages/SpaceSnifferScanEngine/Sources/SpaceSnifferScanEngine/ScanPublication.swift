/// Presentation coalescing, not a filesystem traversal rule. Geometric growth
/// bounds the total node volume copied for intermediate UI snapshots to O(n).
@frozen public struct ScanPublication {
    @inlinable public init() {}
    @usableFromInline var lastCount = 0
    @inlinable public mutating func shouldPublish(nodeCount: Int) -> Bool {
        guard nodeCount > 0, lastCount == 0 || nodeCount - lastCount >= lastCount else { return false }
        lastCount = nodeCount
        return true
    }
}

