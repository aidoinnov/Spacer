import Foundation
import SpaceSnifferScanEngine
enum WindowsTreeBuilder {
    static func scan<Reader: DirectoryBatchReader>(root: String, control: ScanControl, policy: WindowsScanPolicy,
                            boundedReader: Reader, inlineReader: Reader,
                            includeMountedVolumes:Bool = false,rootVolume:String? = nil,
                            progress: @Sendable (WindowsProgress) -> Void) -> WindowsSnapshot where Reader.Output == Batch {
        let start = Date()
        let name = URL(fileURLWithPath: root).lastPathComponent
        var result = WindowsSnapshot(root: root, nodes: [WindowsNode(id: 0, parent: nil, name: name.isEmpty ? root : name,
            path: root, directory: true, logical: 0, allocated: 0, attributes: 0x10, boundary: false, children: [])])
        let budget = DirectoryIOBudget(limit: policy.ioLimit)
        let pool = DirectoryWorkerPool<Batch>(workers: policy.workers, capacity: policy.queueCapacity, budget: budget, cancelledOutput: { .cancelled })
        defer { pool.shutdown() }
        var window = DirectoryReadWindow<Int, Batch>(futureCapacity: policy.futureCapacity)
        var pending = [0]
        var identities = Set<String>()
        var volumes=Set(rootVolume.map {[$0]} ?? [])
        var overview = WindowsOverview()
        var observedLogical: UInt64 = 0, observedAllocated: UInt64 = 0
        var lastProgress = Date.distantPast
        while let id = pending.popLast(), !control.isCancelled {
            let path = result.nodes[id].path
            let batch = window.take(for: id)?.wait() ?? budget.withPermit(control: control) {
                inlineReader.readDirectory(at: path, control: control)
            } ?? .cancelled
            switch batch {
            case .cancelled: control.cancel()
            case .failure(let code): result.nodes[id].error = code; result.errors += 1
            case .retryInline:
                // Retry with unbounded collection only on the builder; worker
                // results stay bounded and cannot retain giant sibling folders.
                switch budget.withPermit(control: control, operation: { inlineReader.readDirectory(at: path, control: control) }) ?? .cancelled {
                case .listing(let entries): add(entries, parent: id, to: &result, pending: &pending, identities: &identities,
                                               logical: &observedLogical, allocated: &observedAllocated, overview: &overview,includeMountedVolumes:includeMountedVolumes,volumes:&volumes)
                case .failure(let code): result.nodes[id].error = code; result.errors += 1
                default: control.cancel()
                }
            case .listing(let entries):
                add(entries, parent: id, to: &result, pending: &pending, identities: &identities,
                    logical: &observedLogical, allocated: &observedAllocated, overview: &overview,includeMountedVolumes:includeMountedVolumes,volumes:&volumes)
            }
            if Date().timeIntervalSince(lastProgress) >= policy.heartbeatSeconds {
                lastProgress = Date()
                progress(WindowsProgress(current: path, files: result.files, folders: result.folders, pending: pending.count,
                    errors: result.errors, excluded: result.excluded, logical: observedLogical, allocated: observedAllocated,
                    roots: overview.roots(result.nodes)))
            }
            if !control.isCancelled {
                window.replenish(from: pending.suffix(8).reversed(), maximumPlans: 8, key: { $0 }, submit: { child in
                    pool.submit(reader: boundedReader, path: result.nodes[child].path, control: control)
                })
            }
        }
        if control.isCancelled {
            pool.cancelQueued(control: control)
            for ticket in window.values { _ = ticket.wait() }
            window.removeAll()
        }
        pool.shutdown()
        result.cancelled = control.isCancelled
        // Builder alone assigns IDs, children and totals. Every child's parent
        // precedes it, so reversed IDs are a valid aggregate order.
        for id in result.nodes.indices where result.nodes[id].directory { result.nodes[id].logical = 0; result.nodes[id].allocated = 0 }
        if result.nodes.count > 1 {
            for id in stride(from: result.nodes.count - 1, through: 1, by: -1) {
                if let parent = result.nodes[id].parent {
                    result.nodes[parent].logical += result.nodes[id].logical
                    result.nodes[parent].allocated += result.nodes[id].allocated
                }
            }
        }
        result.elapsedSeconds = Date().timeIntervalSince(start)
        return result
    }
    private static func add(_ entries: [NativeEntry], parent: Int, to result: inout WindowsSnapshot,
                            pending: inout [Int], identities: inout Set<String>, logical: inout UInt64, allocated: inout UInt64, overview: inout WindowsOverview,includeMountedVolumes:Bool,volumes:inout Set<String>) {
        var rootBranch = parent
        while let ancestor = result.nodes[rootBranch].parent, ancestor != 0 { rootBranch = ancestor }
        var batchLogical: UInt64 = 0, batchAllocated: UInt64 = 0
        for entry in entries {
            let id = result.nodes.count
            let base = result.nodes[parent].path
            let path = base + (base.hasSuffix("\\") || base.hasSuffix("/") ? "" : "\\") + entry.name
            var ownAllocated = entry.allocated
            if let identity = entry.identity, !entry.directory, !identities.insert(identity).inserted { ownAllocated = 0 }
            // Only a native-recognized volume mount can cross the boundary.
            // Junctions/symlinks remain excluded, and each volume is visited once.
            let includedMount=includeMountedVolumes && entry.directory && entry.mountedVolume.map {volumes.insert($0).inserted} == true
            let boundary=entry.reparse && !includedMount
            if boundary { result.excluded += 1; ownAllocated = 0 }
            let ownLogical = boundary ? 0 : entry.logical
            result.nodes.append(WindowsNode(id: id, parent: parent, name: entry.name, path: path, directory: entry.directory,
                logical: ownLogical, allocated: ownAllocated, attributes: entry.attributes, boundary: boundary, children: [],createdTicks:entry.createdTicks,accessedTicks:entry.accessedTicks,modifiedTicks:entry.modifiedTicks))
            result.nodes[parent].children.append(id)
            if parent == 0 { overview.observe(id, nodes: result.nodes) }
            logical += ownLogical; allocated += ownAllocated
            batchLogical += ownLogical; batchAllocated += ownAllocated
            if entry.directory { result.folders += 1; if !boundary { pending.append(id) } }
            else { result.files += 1 }
        }
        if parent != 0 { result.nodes[rootBranch].logical += batchLogical; result.nodes[rootBranch].allocated += batchAllocated; overview.observe(rootBranch, nodes: result.nodes) }
    }
}
