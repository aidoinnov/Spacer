import Foundation

/// Reuses only private ancestor context bytes. Published membership/weights and
/// snapshot pages never enter this pool. One owner per projection session; reset
/// replaces the owner without blocking UI on a running membership pass.
final class FilterScratch: @unchecked Sendable {
    private let lock = NSLock()
    private var contexts: [UInt8] = []
    private let retentionLimit: Int
    init(retentionLimit: Int = 1_048_576) { precondition(retentionLimit >= 0); self.retentionLimit = retentionLimit }
    deinit { ScratchBudget.shared.relinquish(self) }
    func membership(filter: ScanFilter, snapshot: ScanSnapshot, showHidden: Bool, control: ScanControl) -> [Bool]? {
        lock.lock()
        let epoch = ScratchBudget.shared.checkout(self, capacity: contexts.capacity,
            needed: filter.needsAncestorContext || !showHidden ? snapshot.nodes.count : 0)
        // Every visited node overwrites its state from its freshly written parent.
        // A cancelled pass therefore cannot leak inherited flags into a later pass.
        let result = filter.membership(in: snapshot, showHidden: showHidden, control: control, contexts: &contexts)
        ScratchBudget.shared.finish(self, capacity: contexts.capacity, limit: retentionLimit, epoch: epoch) { keep in
            if !keep { contexts = [] }; lock.unlock()
        }
        return result
    }
    var retainedBytes: Int { lock.lock(); defer { lock.unlock() }; return contexts.capacity }
    func evictIfIdle() {
        guard lock.try() else { return }
        contexts = []; lock.unlock()
    }
}
