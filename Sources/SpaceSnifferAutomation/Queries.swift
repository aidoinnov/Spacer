import Foundation
#if canImport(SpaceSnifferCore)
import SpaceSnifferCore
#else
import ExplorerDomain
#endif

public struct QueryContext: Sendable {
    public let snapshot: ScanSnapshot
    public let weights: [Int64]
    public let filter: ScanFilter
    public let mode: SizeMode
    public let showHidden: Bool
    public let revision: String
    public let focus: Int
    public let selection: Int?
    public init(snapshot: ScanSnapshot, weights: [Int64], filter: ScanFilter, mode: SizeMode, showHidden: Bool, revision: String, focus: Int, selection: Int?) {
        self.snapshot = snapshot; self.weights = weights; self.filter = filter; self.mode = mode
        self.showHidden = showHidden; self.revision = revision; self.focus = focus; self.selection = selection
    }
    public func nodeID(path: String?) throws -> Int {
        try Task.checkCancellation()
        guard let path else { return focus }
        guard SnapshotPath.isAbsolute(path), SnapshotTree.contains(snapshot.rootPath, path) else { throw ControlError("not_found", "Path is outside the scanned root") }
        var id = 0
        if path != snapshot.rootPath {
            let separator: Character = SnapshotPath.isWindows(path) ? "\\" : "/"
            for component in path.dropFirst(snapshot.rootPath.count).split(separator: separator) {
                try Task.checkCancellation()
                var found: Int?
                for (position, child) in snapshot.nodes[id].children.enumerated() {
                    if position % 128 == 0 { try Task.checkCancellation() }
                    if snapshot.nodes[child].name == component { found = child; break }
                }
                guard let next = found else { throw ControlError("not_found", "Path not present in this snapshot") }
                id = next
            }
        }
        guard snapshot.nodes.indices.contains(id), snapshot.nodes[id].path == path else { throw ControlError("not_found", "Path not present in this snapshot") }
        return id
    }
    public func node(_ id: Int, inheritedTagMask: Int? = nil) -> JSONValue {
        let n = snapshot.nodes[id]
        var tagMask = inheritedTagMask ?? 0
        if inheritedTagMask == nil {
            var cursor: Int? = id
            while let current = cursor { tagMask |= snapshot.tags[snapshot.nodes[current].path] ?? 0; cursor = snapshot.nodes[current].parent }
        }
        return .object(["id": .int(id), "path": .string(n.path), "name": .string(n.name),
            "parent_path": n.parent.map { .string(snapshot.nodes[$0].path) } ?? .null,
            "is_directory": .bool(n.isDirectory), "logical_bytes": .integer(n.logicalBytes), "allocated_bytes": .integer(n.allocatedBytes),
            "filtered_bytes": weights.indices.contains(id) ? .integer(weights[id]) : .null,
            "child_count": .int(n.children.count), "modified_at": .date(n.modified), "created_at": .date(n.created), "accessed_at": .date(n.accessed),
            "own_tag": .int(snapshot.tags[n.path] ?? 0), "inherited_tag_mask": .int(tagMask),
            "native_attributes": n.nativeAttributes.map { .integer(Int64($0)) } ?? .null,
            "native_flags": n.nativeFlags.map { .int(Int($0)) } ?? .null,
            "native_type": n.nativeType.map { .int(Int($0)) } ?? .null,
            "file_identity": n.fileIdentity.map { .string($0) } ?? .null,
            "issue": n.issue.map { .string($0) } ?? .null])
    }
    private func checkedNode(_ id: Int) throws -> JSONValue {
        var mask = 0, count = 0; var cursor: Int? = id
        while let current = cursor {
            if count % 128 == 0 { try Task.checkCancellation() }
            mask |= snapshot.tags[snapshot.nodes[current].path] ?? 0
            cursor = snapshot.nodes[current].parent; count += 1
        }
        return node(id, inheritedTagMask: mask)
    }
    public func query(command: String, arguments a: [String: JSONValue]) throws -> JSONValue {
        try Task.checkCancellation()
        if let expected = a["revision"]?.string, expected != revision { throw ControlError("stale_revision", "Snapshot changed; restart pagination with the returned revision") }
        let limit = try a.boundedInt("limit", default: 100, range: 1...500)
        let offset = try a.boundedInt("offset", default: 0, range: 0...10_000_000)
        let root = try nodeID(path: a["path"]?.string)
        switch command {
        case "node_info":
            var ancestry: [JSONValue] = []; var cursor: Int? = root
            while let id = cursor {
                if ancestry.count % 128 == 0 { try Task.checkCancellation() }
                ancestry.append(.string(snapshot.nodes[id].path)); cursor = snapshot.nodes[id].parent
            }
            return .object(["revision": .string(revision), "node": try checkedNode(root), "ancestors": .array(ancestry.reversed())])
        case "tree_children":
            let filtered = a["filtered"]?.boolean ?? true
            let children = snapshot.nodes[root].children
            var rows: [JSONValue] = []; var index = min(offset, children.count)
            while index < children.count, rows.count < limit {
                if Task.isCancelled { throw CancellationError() }
                let id = children[index]; index += 1
                if !filtered || weights.indices.contains(id) && weights[id] > 0 { rows.append(try checkedNode(id)) }
            }
            return .object(["revision": .string(revision), "path": .string(snapshot.nodes[root].path), "items": .array(rows),
                "total_children": .int(children.count), "next_offset": index < children.count ? .int(index) : .null, "order": .string("snapshot_child_order")])
        case "query_nodes":
            guard a["traversal"] == nil || ["snapshot", "subtree"].contains(a["traversal"]?.string ?? "") else { throw ControlError("invalid_argument", "Unknown query traversal") }
            guard a["cursor"] == nil, a["cancel_cursor"]?.boolean != true, a["traversal"]?.string != "subtree" else {
                throw ControlError("invalid_argument", "Subtree cursor requests require the window query session")
            }
            let expression = try ScanFilter(a["expression"]?.string ?? "")
            let budget = try a.boundedInt("budget", default: 50000, range: 1...100000)
            let now = Date(); var index = min(offset, snapshot.nodes.count); var inspected = 0; var rows: [JSONValue] = []
            while index < snapshot.nodes.count, rows.count < limit, inspected < budget {
                if index % 1024 == 0 && Task.isCancelled { throw CancellationError() }
                let n = snapshot.nodes[index]; index += 1; inspected += 1
                guard !n.isDirectory, SnapshotTree.contains(snapshot.nodes[root].path, n.path) else { continue }
                if expression.matches(n, snapshot: snapshot, now: now) { rows.append(try checkedNode(n.id)) }
            }
            return .object(["revision": .string(revision), "items": .array(rows), "inspected_nodes": .int(inspected),
                "next_offset": index < snapshot.nodes.count ? .int(index) : .null, "complete": .bool(index == snapshot.nodes.count)])
        case "largest_nodes":
            // A bounded min-heap: no sort or metadata dictionary for the entire tree.
            let kind = a["kind"]?.string ?? "files"
            guard ["files", "folders", "all"].contains(kind) else { throw ControlError("invalid_argument", "kind must be files, folders or all") }
            let filtered = a["filtered"]?.boolean ?? true
            var heap: [(id: Int, bytes: Int64)] = []
            func less(_ a: (id: Int, bytes: Int64), _ b: (id: Int, bytes: Int64)) -> Bool { a.bytes == b.bytes ? a.id > b.id : a.bytes < b.bytes }
            for n in snapshot.nodes {
                if n.id % 1024 == 0 && Task.isCancelled { throw CancellationError() }
                guard n.id != root, SnapshotTree.contains(snapshot.nodes[root].path, n.path),
                      kind == "all" || (kind == "files" ? !n.isDirectory && (n.nativeType == nil || n.nativeType == 2) : n.isDirectory) else { continue }
                let bytes = filtered && weights.indices.contains(n.id) ? weights[n.id] : n.bytes(mode)
                guard bytes > 0 else { continue }
                let candidate = (id: n.id, bytes: bytes)
                if heap.count < limit {
                    heap.append(candidate); var i = heap.count - 1
                    while i > 0 { let parent = (i - 1) / 2; if !less(heap[i], heap[parent]) { break }; heap.swapAt(i, parent); i = parent }
                } else if less(heap[0], candidate) {
                    heap[0] = candidate; var i = 0
                    while i * 2 + 1 < heap.count {
                        var child = i * 2 + 1
                        if child + 1 < heap.count && less(heap[child + 1], heap[child]) { child += 1 }
                        if !less(heap[child], heap[i]) { break }; heap.swapAt(child, i); i = child
                    }
                }
            }
            return .object(["revision": .string(revision), "items": .array(try heap.sorted { less($1, $0) }.map { try checkedNode($0.id) }), "limit": .int(limit)])
        case "scan_issues":
            let end = min(snapshot.issues.count, offset + limit)
            let rows = offset < end ? Array(snapshot.issues[offset..<end]).map { JSONValue.string($0) } : []
            return .object(["revision": .string(revision), "items": .array(rows), "issue_count": .int(snapshot.issueCount),
                "stored_count": .int(snapshot.issues.count), "storage_truncated": .bool(snapshot.issueCount > snapshot.issues.count),
                "next_offset": end < snapshot.issues.count ? .int(end) : .null])
        default: throw ControlError("unknown_command", command)
        }
    }
}
