import Foundation
@testable import SpaceSnifferCore

/// treeMapNodeRemoved (0x42ee60): move focus/history out of a removed subtree,
/// clear a removed selection, then collapse adjacent duplicate history entries.
/// Immutable snapshot paths replace the original stable node pointers.
struct LegacyNavigationState {
    let focus: Int
    let selection: Int?
    let history: [String]
    let historyIndex: Int

    init?(snapshot: ScanSnapshot, previous: ScanSnapshot?, included: [Bool], weights: [Int64],
          focusPath: String?, selectionPath: String?, history: [String], historyIndex: Int,
          control: ScanControl) {
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
        let surviving = TagPolicy.survivingPaths(tracked, previous: previous?.nodes ?? [], current: snapshot.nodes, control: control)
        guard !control.isCancelled else { return nil }
        let selectionPath = selectionPath.flatMap { surviving[$0] }
        let needed = Set(surviving.values)
        var remaining = needed.count
        for node in snapshot.nodes {
            if remaining == 0 { break }
            if node.id % 1024 == 0 && control.isCancelled { return nil }
            guard needed.contains(node.path) else { continue }
            remaining -= 1
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
    }
}
