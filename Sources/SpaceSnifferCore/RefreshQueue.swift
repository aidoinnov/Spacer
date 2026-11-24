import Foundation

/// Weak observation only: inspecting queue lifetime must not keep its arena alive.
final class RefreshQueueStorageWitness: @unchecked Sendable {
    private weak var storage: AnyObject?
    init(_ storage: AnyObject?) { self.storage = storage }
    var isReleased: Bool { storage == nil }
}

/// W09 addRefilterRequest 0x42e130: duplicate/ancestor packing and FIFO.
/// The radix indexes and slot reuse are Mac choices, not original Windows TList internals.
struct RefreshQueue: @unchecked Sendable {
    // Value semantics: a shared Storage is immutable until the writer takes a COW copy.
    private final class Storage {
        private struct Entry { let path: String; var previous: Int?; var next: Int? }
        private var entries: [Entry?] = []
        private var free: [Int] = []
        private var head: Int?; private var tail: Int?
        private var pathsIndex = RefreshPathIndex()
        private var coverageIndex = RefreshPathIndex()
        private(set) var count = 0
        var allocatedSlots: Int { entries.count + pathsIndex.allocatedSlots + coverageIndex.allocatedSlots }
        init(_ paths: [String]) { for path in paths { append(path) } }
        init(copying other: Storage) {
            entries = other.entries; free = other.free; head = other.head; tail = other.tail
            pathsIndex = other.pathsIndex; coverageIndex = other.coverageIndex; count = other.count
        }
        var paths: [String] {
            var result: [String] = []; result.reserveCapacity(count); var cursor = head
            while let id = cursor { let entry = entries[id]!; result.append(entry.path); cursor = entry.next }
            return result
        }
        func covers(_ path: String) -> Bool { pathsIndex.exact(path) != nil || coverageIndex.hasPrefix(of: path) }
        func append(_ path: String) {
            let id = free.popLast() ?? entries.count
            let entry = Entry(path: path, previous: tail)
            if id == entries.count { entries.append(entry) } else { entries[id] = entry }
            if let tail { entries[tail]!.next = id } else { head = id }
            tail = id; count += 1
            pathsIndex.insert(path, id: id); coverageIndex.insert(RefreshQueue.prefix(path), id: id)
        }
        private func remove(_ id: Int) {
            let entry = entries[id]!
            pathsIndex.remove(entry.path); coverageIndex.remove(RefreshQueue.prefix(entry.path))
            if let previous = entry.previous { entries[previous]!.next = entry.next } else { head = entry.next }
            if let next = entry.next { entries[next]!.previous = entry.previous } else { tail = entry.previous }
            entries[id] = nil; free.append(id); count -= 1
        }
        func removeCovered(by scope: String) {
            let prefix = RefreshQueue.prefix(scope)
            var affected = pathsIndex.prefixed(by: prefix)
            if prefix != scope, let exact = pathsIndex.exact(scope) { affected.append(exact) }
            if !affected.isEmpty, affected.count == count {
                entries = []; free = []; head = nil; tail = nil; count = 0
                pathsIndex = RefreshPathIndex(); coverageIndex = RefreshPathIndex()
            } else { for id in affected { remove(id) } }
        }
        func popFirst() -> String? {
            guard let head else { return nil }; let path = entries[head]!.path; remove(head); return path
        }
    }
    private var small: [String] = []
    private var storage: Storage?
    var paths: [String] { storage?.paths ?? small }
    var isEmpty: Bool { storage.map { $0.count == 0 } ?? small.isEmpty }
    /// Diagnostics count slots, not bytes or process RSS. Empty queues retain no index arena.
    var indexSlots: Int { storage?.allocatedSlots ?? 0 }
    var count: Int { storage?.count ?? small.count }
    var storageWitness: RefreshQueueStorageWitness { RefreshQueueStorageWitness(storage) }
    private static func prefix(_ path: String) -> String {
        path.hasSuffix("/") || path.hasSuffix("\\") ? path : path + (SnapshotPath.isWindows(path) ? "\\" : "/")
    }
    private mutating func makeUnique() {
        if !isKnownUniquelyReferenced(&storage) { storage = Storage(copying: storage!) }
    }
    mutating func insert(_ path: String) {
        if storage == nil {
            guard !small.contains(where: { SnapshotTree.contains($0, path) }) else { return }
            small.removeAll { SnapshotTree.contains(path, $0) }; small.append(path)
            if small.count > 16 { storage = Storage(small); small = [] }
        } else {
            makeUnique(); let index = storage!
            guard !index.covers(path) else { return }
            index.removeCovered(by: path); index.append(path); rebalance()
        }
    }
    mutating func removeCovered(by scope: String) {
        if storage == nil { small.removeAll { SnapshotTree.contains(scope, $0) } }
        else { makeUnique(); storage!.removeCovered(by: scope); rebalance() }
    }
    mutating func popFirst() -> String? {
        if storage == nil { return small.isEmpty ? nil : small.removeFirst() }
        makeUnique(); let path = storage!.popFirst(); rebalance(); return path
    }
    mutating func removeAll() { small = []; storage = nil }
    private mutating func rebalance() {
        guard let index = storage else { return }
        if index.count <= 8 { small = index.paths; storage = nil }
        else if index.allocatedSlots > max(128, index.count * 12) { storage = Storage(index.paths) }
    }
}
