import Foundation

/// Verified size/timestamp-only payload, bound to two opaque source identities.
/// Unknown topology/metadata and dense page changes are deliberately full fallbacks.
struct ProjectionDelta: Sendable {
    let baselineID: UUID
    let resultID: UUID
    let changedIDs: [Int]
    init?(baseline: ProjectionSource, result: ProjectionSource, control: ScanControl) {
        let old = baseline.snapshot; let new = result.snapshot
        guard old.rootPath == new.rootPath, old.tags == new.tags,
              let ids = new.nodes.differingNodeIDs(from: old.nodes, control: control) else { return nil }
        for id in ids {
            let before = old.nodes[id]; var after = new.nodes[id]
            guard before.path.utf8.elementsEqual(after.path.utf8), before.name.utf8.elementsEqual(after.name.utf8),
                  after.logicalBytes >= 0, after.allocatedBytes >= 0 else { return nil }
            after.logicalBytes = before.logicalBytes; after.allocatedBytes = before.allocatedBytes
            after.ownAllocatedBytes = before.ownAllocatedBytes
            after.modified = before.modified; after.accessed = before.accessed
            guard before == after else { return nil }
        }
        baselineID = baseline.identity; resultID = result.identity; changedIDs = ids
    }
    func apply(previous: ProjectionEvaluation, baseline: ProjectionSource, result: ProjectionSource, filter: ScanFilter,
               mode: SizeMode, showHidden: Bool, control: ScanControl) -> ProjectionEvaluation? {
        guard baseline.identity == baselineID, result.identity == resultID, !filter.isTimeDependent,
              previous.weights.count == result.snapshot.nodes.count, previous.included.count == previous.weights.count else { return nil }
        let started = DispatchTime.now().uptimeNanoseconds
        defer { WorkerTelemetry.shared.observe("filter.delta.apply", nanoseconds: DispatchTime.now().uptimeNanoseconds &- started) }
        var included = previous.included; var weights = previous.weights
        var membershipChanged = false; var weightChanged = false
        struct Change { var removed: Int64 = 0; var added: Int64 = 0 }
        var changes: [Int: Change] = [:]
        for id in changedIDs {
            if control.isCancelled { return nil }
            let node = result.snapshot.nodes[id]
            guard !node.isDirectory else { continue }
            var hidden = false; var ancestor: Int? = id
            if !showHidden {
                while let value = ancestor {
                    if (result.snapshot.nodes[value].nativeAttributes ?? 0) & 2 != 0 { hidden = true; break }
                    ancestor = result.snapshot.nodes[value].parent
                }
            }
            let matches = !hidden && (filter.isEmpty || filter.matches(node, snapshot: result.snapshot))
            if included[id] != matches { included[id] = matches; membershipChanged = true }
            let old = previous.included[id] ? baseline.snapshot.nodes[id].bytes(mode) : 0
            let new = matches ? node.bytes(mode) : 0
            if old == new { continue }
            ancestor = id
            while let value = ancestor {
                var change = changes[value] ?? Change()
                let remove = change.removed.addingReportingOverflow(old); let add = change.added.addingReportingOverflow(new)
                guard !remove.overflow, !add.overflow else { return nil }
                change.removed = remove.partialValue; change.added = add.partialValue; changes[value] = change
                ancestor = result.snapshot.nodes[value].parent
            }
        }
        // Remove all old contributions first. Positive/negative leaf changes cannot
        // create an intermediate overflow when the final aggregate is valid.
        for (id, change) in changes where change.removed != change.added {
            guard change.removed <= weights[id] else { return nil }
            let value = (weights[id] - change.removed).addingReportingOverflow(change.added)
            guard !value.overflow, value.partialValue >= 0 else { return nil }
            weights[id] = value.partialValue; weightChanged = true
        }
        guard !control.isCancelled else { return nil }
        return membershipChanged || weightChanged ? ProjectionEvaluation(included: included, weights: weights) : previous
    }
}
