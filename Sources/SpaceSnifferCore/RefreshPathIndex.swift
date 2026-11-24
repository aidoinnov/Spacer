import Foundation

/// Compressed Character radix index. Character equality preserves Swift's
/// canonical-equivalent String prefix semantics; paths are never normalized.
/// Flat node slots avoid recursive ARC teardown on deep/long input.
struct RefreshPathIndex {
    private struct Node {
        var label: Substring = ""
        var terminal: Int?
        var children: [Character: Int] = [:]
    }
    private var nodes = [Node()]
    private var free: [Int] = []
    var allocatedSlots: Int { nodes.count }
    private mutating func allocate(_ node: Node) -> Int {
        if let id = free.popLast() { nodes[id] = node; return id }
        nodes.append(node); return nodes.count - 1
    }
    private mutating func release(_ id: Int) { nodes[id] = Node(); free.append(id) }
    mutating func insert(_ key: String, id: Int) {
        var cursor = 0; var rest = key[...]
        while let first = rest.first {
            guard let child = nodes[cursor].children[first] else {
                let leaf = allocate(Node(label: rest, terminal: id)); nodes[cursor].children[first] = leaf; return
            }
            let label = nodes[child].label
            var a = label.startIndex; var b = rest.startIndex
            while a != label.endIndex, b != rest.endIndex, label[a] == rest[b] { label.formIndex(after: &a); rest.formIndex(after: &b) }
            if a == label.endIndex { cursor = child; rest = rest[b...]; continue }
            let suffix = label[a...]
            // An internal edge outlives the original terminal. Own the short prefix
            // instead of retaining that terminal's potentially very long String.
            let ownedPrefix = String(label[..<a])
            let split = allocate(Node(label: ownedPrefix[...], children: [suffix.first!: child]))
            nodes[child].label = suffix; nodes[cursor].children[first] = split
            if b == rest.endIndex { nodes[split].terminal = id }
            else {
                let remaining = rest[b...]; let leaf = allocate(Node(label: remaining, terminal: id))
                nodes[split].children[remaining.first!] = leaf
            }
            return
        }
        precondition(nodes[cursor].terminal == nil)
        nodes[cursor].terminal = id
    }
    func exact(_ key: String) -> Int? {
        var cursor = 0; var rest = key[...]
        while let first = rest.first {
            guard let child = nodes[cursor].children[first] else { return nil }
            let label = nodes[child].label
            var a = label.startIndex; var b = rest.startIndex
            while a != label.endIndex, b != rest.endIndex, label[a] == rest[b] { label.formIndex(after: &a); rest.formIndex(after: &b) }
            guard a == label.endIndex else { return nil }
            cursor = child; rest = rest[b...]
        }
        return nodes[cursor].terminal
    }
    func hasPrefix(of key: String) -> Bool {
        var cursor = 0; var rest = key[...]
        if nodes[0].terminal != nil { return true }
        while let first = rest.first {
            guard let child = nodes[cursor].children[first] else { return false }
            let label = nodes[child].label
            var a = label.startIndex; var b = rest.startIndex
            while a != label.endIndex, b != rest.endIndex, label[a] == rest[b] { label.formIndex(after: &a); rest.formIndex(after: &b) }
            guard a == label.endIndex else { return false }
            cursor = child; rest = rest[b...]
            if nodes[cursor].terminal != nil { return true }
        }
        return false
    }
    func prefixed(by prefix: String) -> [Int] {
        var cursor = 0; var rest = prefix[...]
        while let first = rest.first {
            guard let child = nodes[cursor].children[first] else { return [] }
            let label = nodes[child].label
            var a = label.startIndex; var b = rest.startIndex
            while a != label.endIndex, b != rest.endIndex, label[a] == rest[b] { label.formIndex(after: &a); rest.formIndex(after: &b) }
            if b == rest.endIndex { cursor = child; break }
            guard a == label.endIndex else { return [] }
            cursor = child; rest = rest[b...]
        }
        var result: [Int] = []; var stack = [cursor]
        while let id = stack.popLast() {
            if let terminal = nodes[id].terminal { result.append(terminal) }
            stack.append(contentsOf: nodes[id].children.values)
        }
        return result
    }
    mutating func remove(_ key: String) {
        var cursor = 0; var rest = key[...]
        var trace: [(parent: Int, first: Character, child: Int)] = []
        while let first = rest.first {
            guard let child = nodes[cursor].children[first] else { preconditionFailure("missing radix key") }
            let label = nodes[child].label
            var a = label.startIndex; var b = rest.startIndex
            while a != label.endIndex, b != rest.endIndex, label[a] == rest[b] { label.formIndex(after: &a); rest.formIndex(after: &b) }
            precondition(a == label.endIndex)
            trace.append((cursor, first, child)); cursor = child; rest = rest[b...]
        }
        precondition(nodes[cursor].terminal != nil); nodes[cursor].terminal = nil
        for step in trace.reversed() {
            let id = step.child
            if nodes[id].terminal != nil { break }
            if nodes[id].children.isEmpty {
                nodes[step.parent].children[step.first] = nil; release(id)
            } else if nodes[id].children.count == 1, let child = nodes[id].children.values.first {
                let joined = String(nodes[id].label) + nodes[child].label
                nodes[id].label = joined[...]
                nodes[id].terminal = nodes[child].terminal; nodes[id].children = nodes[child].children
                release(child)
            } else { break }
        }
    }
}
