import Foundation

public enum SnapshotTree {
    /// Follow the hierarchy instead of searching every file in unrelated branches.
    public static func nodeID(at path: String, in snapshot: ScanSnapshot) -> Int? {
        guard !snapshot.nodes.isEmpty, contains(snapshot.rootPath, path) else { return nil }
        if path == snapshot.rootPath { return 0 }
        let separator: Character = SnapshotPath.isWindows(snapshot.rootPath) ? "\\" : "/"
        var cursor = 0
        for component in path.dropFirst(snapshot.rootPath.count).split(separator: separator) {
            guard let next = snapshot.nodes[cursor].children.first(where: { snapshot.nodes[$0].name == component }) else { return nil }
            cursor = next
        }
        return snapshot.nodes[cursor].path == path ? cursor : nil
    }

    private static func updateMetadata(_ result: inout ScanSnapshot, from original: ScanSnapshot, subtree: ScanSnapshot) {
        let scope = subtree.rootPath
        let oldIssues = original.issues.filter { !$0.hasPrefix(scope + ":") && !$0.hasPrefix(scope + "/") }
        result.issues = Array((oldIssues + subtree.issues).prefix(500)); result.issueCount = oldIssues.count + subtree.issueCount
        result.started = subtree.started; result.finished = Date(); result.cancelled = false
        result.volumeTotal = subtree.volumeTotal; result.volumeFree = subtree.volumeFree
        if var coverage = original.volumeCoverage {
            let retained = coverage.exclusions.filter { !contains(scope, $0.path) }
            let added = subtree.volumeCoverage?.exclusions ?? []
            coverage.excludedCount = retained.count + (subtree.volumeCoverage?.excludedCount ?? 0)
            coverage.exclusions = Array((retained + added).prefix(500))
            result.volumeCoverage = coverage
        }
    }
    public static func contains(_ root: String, _ path: String) -> Bool {
        path == root || path.hasPrefix(root.hasSuffix("/") || root.hasSuffix("\\") ? root : root + (SnapshotPath.isWindows(root) ? "\\" : "/"))
    }
    /// Replace one complete subtree, then rebuild IDs and ancestor totals on the scan worker.
    /// Each directory entry contributes its own size, matching native new-node + deltaSize aggregation.
    public static func replacing(_ original: ScanSnapshot, with subtree: ScanSnapshot, control: ScanControl) -> ScanSnapshot? {
        let scope = subtree.rootPath
        guard contains(original.rootPath, scope), !subtree.cancelled, !subtree.nodes.isEmpty else { return nil }
        // Omitted issue paths cannot be assigned to this scope. The scan worker
        // escalates such inputs to a root refresh before calling the merge.
        guard original.issueCount <= original.issues.count || scope == original.rootPath else { return nil }
        guard original.volumeCoverage.map({ $0.excludedCount <= $0.exclusions.count }) ?? true else { return nil }
        if let before = original.volumeCoverage, let after = subtree.volumeCoverage,
           before.traversal != after.traversal { return nil }
        // Reindex directly from the two flat trees. A dictionary of complete
        // DiskNode values plus another path/children dictionary multiplies peak
        // memory for a one-file change in a multi-million-node root.
        let existing = nodeID(at: scope, in: original)
        if let existing, original.fileCount + original.folderCount == original.nodes.count {
            // Native deltaSize keeps existing nodes when only metadata/size
            // changes. Preserve IDs and untouched pages in the Mac snapshot.
            var result = original
            var work = [(existing, 0)]
            var sameTopology = true
            while let (oldID, newID) = work.popLast() {
                if control.isCancelled { return nil }
                let old = original.nodes[oldID]
                var new = subtree.nodes[newID]
                guard old.path == new.path, old.isDirectory == new.isDirectory, old.nativeType == new.nativeType,
                      old.children.count == new.children.count else { sameTopology = false; break }
                for pair in zip(old.children, new.children) { work.append(pair) }
                new.id = oldID; new.parent = old.parent; new.children = old.children
                if new != old { result.nodes[oldID] = new }
            }
            if sameTopology {
                let logicalDelta = subtree.nodes[0].logicalBytes - original.nodes[existing].logicalBytes
                let allocatedDelta = subtree.nodes[0].allocatedBytes - original.nodes[existing].allocatedBytes
                var parent = original.nodes[existing].parent
                while let id = parent {
                    if control.isCancelled { return nil }
                    let logical = result.nodes[id].logicalBytes.addingReportingOverflow(logicalDelta)
                    let allocated = result.nodes[id].allocatedBytes.addingReportingOverflow(allocatedDelta)
                    guard !logical.overflow, !allocated.overflow, logical.partialValue >= 0, allocated.partialValue >= 0 else { return nil }
                    if logicalDelta != 0 { result.nodes[id].logicalBytes = logical.partialValue }
                    if allocatedDelta != 0 { result.nodes[id].allocatedBytes = allocated.partialValue }
                    parent = original.nodes[id].parent
                }
                updateMetadata(&result, from: original, subtree: subtree)
                return result
            }
        }
        guard !control.isCancelled else { return nil }
        let parentPath = URL(fileURLWithPath: scope).deletingLastPathComponent().path
        let candidateParent = existing == nil ? nodeID(at: parentPath, in: original) : nil
        let insertionParent = candidateParent.flatMap { original.nodes[$0].isDirectory ? $0 : nil }
        guard existing != nil || insertionParent != nil else { return nil }
        var removedCount = 0
        var removed = existing.map { [$0] } ?? []
        while let id = removed.popLast() {
            if control.isCancelled { return nil }
            removedCount += 1; removed.append(contentsOf: original.nodes[id].children)
        }
        var result = original; result.nodes = []; result.fileCount = 0; result.folderCount = 0
        result.nodes.reserveCapacity(original.nodes.count - removedCount + subtree.nodes.count)
        result.finished = Date(); result.cancelled = false
        // source=true refers to the new subtree; otherwise to the original.
        var stack: [(source: Bool, id: Int, parent: Int?)] = [(false, 0, nil)]
        while let work = stack.popLast() {
            if control.isCancelled { return nil }
            let replace = !work.source && work.id == existing
            let source = work.source || replace
            let sourceID = replace ? 0 : work.id
            let nodes = source ? subtree.nodes : original.nodes
            var node = nodes[sourceID]
            let children = node.children.sorted { nodes[$0].path < nodes[$1].path }
            node.id = result.nodes.count; node.parent = work.parent; node.children = []
            node.logicalBytes = node.isDirectory ? 0 : node.logicalBytes
            node.allocatedBytes = node.isDirectory ? 0 : node.ownAllocatedBytes ?? node.allocatedBytes
            node.ownAllocatedBytes = node.isDirectory ? 0 : node.allocatedBytes
            if let parent = work.parent { result.nodes[parent].children.append(node.id) }
            result.nodes.append(node)
            if node.isDirectory {
                result.folderCount += 1
                var jobs = children.map { (source: source, id: $0, parent: Optional(node.id)) }
                if !source && work.id == insertionParent {
                    let index = children.firstIndex { nodes[$0].path > scope } ?? children.count
                    jobs.insert((true, 0, node.id), at: index)
                }
                stack.append(contentsOf: jobs.reversed())
            } else { result.fileCount += 1 }
        }
        if result.nodes.count > 1 {
            for i in stride(from: result.nodes.count - 1, through: 1, by: -1) {
                if let p = result.nodes[i].parent {
                    result.nodes[p].logicalBytes += result.nodes[i].logicalBytes
                    result.nodes[p].allocatedBytes += result.nodes[i].allocatedBytes
                }
            }
        }
        updateMetadata(&result, from: original, subtree: subtree)
        return result
    }
}
