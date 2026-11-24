import Foundation

/// treeMapNodeRemoved (0x42ee60): move focus/history out of a removed subtree,
/// clear a removed selection, then collapse adjacent duplicate history entries.
/// Immutable snapshot paths replace the original stable node pointers.
struct NavigationState {
    let focus: Int
    let selection: Int?
    let history: [String]
    let historyIndex: Int
    let trackedLookup: [String: Int]

    init?(snapshot: ScanSnapshot, previous: ScanSnapshot?, included: [Bool], weights: [Int64],
          focusPath: String?, selectionPath: String?, history: [String], historyIndex: Int,
          control: ScanControl, lookup: [String: Int] = [:]) {
        var directories: [String: Int] = [:]
        var selected: Int?
        var tracked = Set(history + [focusPath, selectionPath].compactMap { $0 })
        // Retain ancestors of the handful of tracked paths, not a parent entry
        // for every file. Snapshot paths are already validated absolute paths.
        func parent(of path: String) -> String? {
            guard path != snapshot.rootPath else { return nil }
            let separator: Character = SnapshotPath.isWindows(path) ? "\\" : "/"
            guard let end = path.lastIndex(of: separator) else { return nil }
            var result = end == path.startIndex ? String(separator) : String(path[..<end])
            if SnapshotPath.isWindows(path), result.count == 2, result.last == ":" { result.append(separator) }
            return SnapshotTree.contains(snapshot.rootPath, result) ? result : nil
        }
        for path in Array(tracked) {
            var cursor = parent(of: path)
            while let path = cursor { tracked.insert(path); cursor = parent(of: path) }
        }
        var resolved: [String: Int] = [:]
        var missing = tracked
        for path in tracked {
            if let id = lookup[path], snapshot.nodes.indices.contains(id), snapshot.nodes[id].path == path {
                resolved[path] = id; missing.remove(path)
            }
        }
        // A few new tracked paths can be resolved by hierarchy without visiting
        // every file. Preserve the full scan fallback for imported ambiguous
        // names and large histories, where repeated sibling searches cost more.
        if missing.count <= 64 {
            for path in Array(missing) {
                if control.isCancelled { return nil }
                if let id = SnapshotTree.nodeID(at: path, in: snapshot) {
                    resolved[path] = id; missing.remove(path)
                }
            }
        }
        if !missing.isEmpty {
            for node in snapshot.nodes {
                if node.id % 1024 == 0 && control.isCancelled { return nil }
                if missing.remove(node.path) != nil { resolved[node.path] = node.id }
                if missing.isEmpty { break }
            }
        }
        var surviving = Dictionary(uniqueKeysWithValues: resolved.keys.map { ($0, $0) })
        if let previous, !previous.nodes.sharesStorage(with: snapshot.nodes) {
            // Stable IDs are the common case for metadata updates. Only seek
            // old paths whose IDs moved; do not build a whole-tree dictionary.
            var before: [String: Int] = [:]
            var unmapped = Set(resolved.keys)
            for (path, id) in resolved where previous.nodes.indices.contains(id) && previous.nodes[id].path == path {
                before[path] = id; unmapped.remove(path)
            }
            if unmapped.count <= 64 {
                for path in Array(unmapped) {
                    if control.isCancelled { return nil }
                    if let id = SnapshotTree.nodeID(at: path, in: previous) { before[path] = id; unmapped.remove(path) }
                }
            } else {
                for node in previous.nodes {
                    if node.id % 1024 == 0 && control.isCancelled { return nil }
                    if unmapped.remove(node.path) != nil { before[node.path] = node.id }
                    if unmapped.isEmpty { break }
                }
            }
            for (path, id) in before {
                guard let currentID = resolved[path], let oldIdentity = previous.nodes[id].fileIdentity,
                      let newIdentity = snapshot.nodes[currentID].fileIdentity, oldIdentity != newIdentity else { continue }
                surviving[path] = nil; missing.insert(path)
            }
        }
        if !missing.isEmpty {
            surviving.merge(TagPolicy.survivingPaths(missing, previous: previous?.nodes ?? [], current: snapshot.nodes, control: control)) { _, new in new }
        }
        guard !control.isCancelled else { return nil }
        let selectionPath = selectionPath.flatMap { surviving[$0] }
        let needed = Set(surviving.values)
        var unmapped = needed.subtracting(resolved.keys)
        if !unmapped.isEmpty {
            for node in snapshot.nodes {
                if node.id % 1024 == 0 && control.isCancelled { return nil }
                if unmapped.remove(node.path) != nil { resolved[node.path] = node.id }
                if unmapped.isEmpty { break }
            }
        }
        for path in needed {
            guard let id = resolved[path] else { continue }
            let node = snapshot.nodes[id]
            let visible = node.isDirectory ? node.parent == nil || weights[node.id] > 0 : included[node.id]
            if node.isDirectory && visible { directories[node.path] = node.id }
            if node.path == selectionPath && visible { selected = node.id }
        }
        func survivingDirectory(_ path: String?) -> Int {
            var cursor = path
            while let path = cursor {
                if let id = directories[surviving[path] ?? path] { return id }
                cursor = parent(of: path)
            }
            return 0
        }
        focus = survivingDirectory(focusPath)
        selection = selected
        var repaired: [String] = []
        var repairedIndex = -1
        for (index, path) in history.enumerated() {
            if control.isCancelled { return nil }
            let id = survivingDirectory(path)
            guard snapshot.nodes.indices.contains(id) else { continue }
            let path = snapshot.nodes[id].path
            if repaired.last != path { repaired.append(path) }
            if index <= historyIndex { repairedIndex = repaired.count - 1 }
        }
        if repaired.isEmpty, !snapshot.nodes.isEmpty { repaired = [snapshot.rootPath]; repairedIndex = 0 }
        self.history = repaired
        self.historyIndex = repairedIndex
        // No whole-tree dictionary. Oversized histories still work via fallback.
        var bounded: [String: Int] = [:]; var bytes = 0
        for (path, id) in resolved where bounded.count < 4096 {
            let size = path.utf8.count
            if size <= 1_048_576 - bytes { bounded[path] = id; bytes += size }
        }
        trackedLookup = bounded
    }
}
