import Foundation
#if canImport(SpaceSnifferCore)
import SpaceSnifferCore
#else
import ExplorerDomain
#endif

/// Mac automation extension. A cursor retains one immutable revision, never a UI/store.
/// Legacy query_nodes offset semantics remain in QueryContext.query.
public final class SubtreeQuerySession: @unchecked Sendable {
    public struct Statistics: Sendable {
        public let cursors: Int, activePages: Int, maximumCursors: Int, maximumFramesPerCursor: Int
        public let created: Int, reusedContexts: Int, evicted: Int, cancelled: Int
    }
    private final class Lease: Sendable {
        let context: QueryContext
        init(_ context: QueryContext) { self.context = context }
    }
    private struct Frame {
        let id: Int
        var nextChild: Int = -1
        let tags: Int
    }
    // The session lock owns the dictionary/token/busy/lastUsed fields. Exactly one
    // checked-out page owns stack mutation; cancellation uses ScanControl's lock.
    private final class Cursor: @unchecked Sendable {
        let lease: Lease, root: Int, expression: ScanFilter, now: Date
        let control = ScanControl()
        var stack: [Frame]
        var token: String, busy = false, lastUsed: TimeInterval
        init(lease: Lease, root: Int, expression: ScanFilter, tags: Int, uptime: TimeInterval) {
            self.lease = lease; self.root = root; self.expression = expression; now = Date()
            stack = [Frame(id: root, tags: tags)]; token = UUID().uuidString; lastUsed = uptime
        }
    }
    private let lock = NSLock()
    private var entries: [String: Cursor] = [:]
    private var lease: Lease?
    private var ownerEpoch = UUID()
    private var closed = false
    private var activePages = 0
    private let maximumCursors: Int, maximumFrames: Int
    private var created = 0, reusedContexts = 0, evicted = 0, cancelled = 0
    private let idleSeconds: TimeInterval = 60
    private let willRunPage: (@Sendable () -> Void)?
    private let uptime: @Sendable () -> TimeInterval
    public init(maximumCursors: Int = 8, maximumFramesPerCursor: Int = 4096) {
        self.maximumCursors = max(1, min(8, maximumCursors))
        maximumFrames = max(1, min(4096, maximumFramesPerCursor))
        willRunPage = nil
        uptime = { ProcessInfo.processInfo.systemUptime }
    }
    // A request-boundary seam for deterministic running/reset/cancel ownership
    // tests. Production has no observer and no per-node callback.
    init(maximumCursors: Int, maximumFramesPerCursor: Int = 4096, willRunPage: @escaping @Sendable () -> Void,
         uptime: @escaping @Sendable () -> TimeInterval = { ProcessInfo.processInfo.systemUptime }) {
        self.maximumCursors = max(1, min(8, maximumCursors))
        maximumFrames = max(1, min(4096, maximumFramesPerCursor)); self.willRunPage = willRunPage
        self.uptime = uptime
    }
    public var statistics: Statistics {
        lock.lock(); defer { lock.unlock() }
        return Statistics(cursors: entries.count, activePages: activePages,
            maximumCursors: maximumCursors, maximumFramesPerCursor: maximumFrames,
            created: created, reusedContexts: reusedContexts, evicted: evicted, cancelled: cancelled)
    }
    /// Capture beside the frozen context, before dispatching detached work.
    /// A reset between capture and cursor creation then rejects that old request.
    public var epoch: UUID { lock.lock(); defer { lock.unlock() }; return ownerEpoch }
    /// Called whenever the owner publishes another revision or shuts down. A page
    /// already running holds its own immutable lease only until cooperative exit.
    public func reset() {
        lock.lock(); defer { lock.unlock() }
        resetLocked()
    }
    /// Terminal owner boundary: queued requests cannot reopen a closed window's
    /// cursor session even if they did not supply an epoch.
    public func shutdown() {
        lock.lock(); defer { lock.unlock() }
        closed = true; resetLocked()
    }
    private func resetLocked() {
        ownerEpoch = UUID()
        for cursor in entries.values { cursor.control.cancel() }
        entries.removeAll(keepingCapacity: false); lease = nil
    }
    deinit { shutdown() }
    var contextLeaseWitness: AnyObject? {
        lock.lock(); defer { lock.unlock() }; return lease
    }

    public func query(context: QueryContext, arguments a: [String: JSONValue], epoch: UUID? = nil) throws -> JSONValue {
        try Task.checkCancellation()
        let requestEpoch = epoch ?? self.epoch
        guard a["traversal"]?.string == "subtree" else { throw ControlError("invalid_argument", "Use traversal=subtree for a cursor request") }
        if let expected = a["revision"]?.string, expected != context.revision {
            throw ControlError("stale_revision", "Snapshot changed; restart subtree pagination")
        }
        guard a["offset"] == nil || a["offset"]?.integer == 0 else { throw ControlError("invalid_argument", "Subtree cursors cannot be combined with a nonzero offset") }
        let limit = try a.boundedInt("limit", default: 100, range: 1...500)
        let budget = try a.boundedInt("budget", default: 50000, range: 1...100000)
        let cancel = a["cancel_cursor"]?.boolean ?? false
        let cursor: Cursor
        if let token = a["cursor"]?.string {
            cursor = try checkout(token: token, context: context, arguments: a, cancel: cancel, epoch: requestEpoch)
            if cancel { return .object(["revision": .string(context.revision), "cancelled": .bool(true), "next_cursor": .null, "complete": .bool(true)]) }
        } else {
            guard !cancel else { throw ControlError("invalid_argument", "cancel_cursor requires cursor") }
            let root = try context.nodeID(path: a["path"]?.string)
            let expression = try ScanFilter(a["expression"]?.string ?? "")
            var tags = 0, ancestors = 0; var id: Int? = root
            while let current = id {
                try Task.checkCancellation()
                guard ancestors < maximumFrames else { throw ControlError("query_limit", "Subtree ancestor depth exceeds the cursor limit; use snapshot traversal") }
                tags |= context.snapshot.tags[context.snapshot.nodes[current].path] ?? 0
                id = context.snapshot.nodes[current].parent; ancestors += 1
            }
            cursor = try create(context: context, root: root, expression: expression, tags: tags, epoch: requestEpoch)
        }
        do {
            willRunPage?()
            var rows: [JSONValue] = []; var inspected = 0, steps = 0
            while !cursor.stack.isEmpty, rows.count < limit, steps < budget {
                try check(cursor)
                let last = cursor.stack.count - 1
                let frame = cursor.stack[last]
                let n = cursor.lease.context.snapshot.nodes[frame.id]
                steps += 1
                if frame.nextChild == -1 {
                    cursor.stack[last].nextChild = 0; inspected += 1
                    if !n.isDirectory && cursor.expression.matches(n, snapshot: cursor.lease.context.snapshot, now: cursor.now, inheritedTagMask: frame.tags) {
                        rows.append(cursor.lease.context.node(n.id, inheritedTagMask: frame.tags))
                    }
                } else if frame.nextChild < n.children.count {
                    guard cursor.stack.count < maximumFrames else { throw ControlError("query_limit", "Subtree depth exceeds the cursor limit; use snapshot traversal") }
                    let child = n.children[frame.nextChild]; cursor.stack[last].nextChild += 1
                    guard cursor.lease.context.snapshot.nodes.indices.contains(child), cursor.lease.context.snapshot.nodes[child].parent == frame.id else {
                        throw ControlError("invalid_snapshot", "Subtree child relation is invalid")
                    }
                    let tags = frame.tags | (cursor.lease.context.snapshot.tags[cursor.lease.context.snapshot.nodes[child].path] ?? 0)
                    cursor.stack.append(Frame(id: child, tags: tags))
                } else { cursor.stack.removeLast() }
            }
            try check(cursor)
            let next = try commit(cursor)
            return .object(["revision": .string(context.revision), "path": .string(cursor.lease.context.snapshot.nodes[cursor.root].path),
                "items": .array(rows), "inspected_nodes": .int(inspected), "traversal_steps": .int(steps),
                "next_offset": .null, "next_cursor": next.map(JSONValue.string) ?? .null,
                "complete": .bool(next == nil), "order": .string("subtree_depth_first"), "evaluated_at": .date(cursor.now)])
        } catch { discard(cursor); throw error }
    }
    private func check(_ cursor: Cursor) throws {
        try Task.checkCancellation()
        if cursor.control.isCancelled { throw CancellationError() }
    }
    private func expire(uptime: TimeInterval) {
        // Lock held. Active pages are never evicted to admit extra work.
        let expired = entries.filter { !$0.value.busy && uptime - $0.value.lastUsed >= idleSeconds }.map(\.key)
        for token in expired { entries[token]?.control.cancel(); entries[token] = nil; evicted += 1 }
        if entries.isEmpty { lease = nil }
    }
    private func checkEpochLocked(_ expected: UUID) throws {
        guard !closed else { throw ControlError("cancelled", "Query owner has shut down") }
        guard expected == ownerEpoch else { throw ControlError("stale_revision", "Query owner changed before the page started; restart pagination") }
    }
    private func create(context: QueryContext, root: Int, expression: ScanFilter, tags: Int, epoch: UUID) throws -> Cursor {
        lock.lock(); defer { lock.unlock() }
        try checkEpochLocked(epoch)
        let uptime = uptime(); expire(uptime: uptime)
        guard activePages < maximumCursors else { throw ControlError("busy", "All subtree page slots are active") }
        if let lease, lease.context.revision != context.revision || !lease.context.snapshot.nodes.sharesStorage(with: context.snapshot.nodes) {
            for cursor in entries.values { cursor.control.cancel() }; entries.removeAll(); self.lease = nil
        }
        // A reset/cancel removes the token immediately, but its running page
        // keeps a slot until it actually exits. Idle cursors cannot crowd out
        // those retired in-flight leases and multiply retained frame buffers.
        let retiredPages = activePages - entries.values.filter(\.busy).count
        if entries.count + retiredPages >= maximumCursors {
            guard let oldest = entries.filter({ !$0.value.busy }).min(by: { $0.value.lastUsed < $1.value.lastUsed }) else {
                throw ControlError("busy", "All subtree cursor slots have an active page")
            }
            oldest.value.control.cancel(); entries[oldest.key] = nil; evicted += 1
        }
        let bound: Lease
        if let lease { bound = lease; reusedContexts += 1 }
        else { bound = Lease(context); lease = bound }
        let cursor = Cursor(lease: bound, root: root, expression: expression, tags: tags, uptime: uptime)
        cursor.busy = true; activePages += 1; entries[cursor.token] = cursor; created += 1; return cursor
    }
    private func checkout(token: String, context: QueryContext, arguments a: [String: JSONValue], cancel: Bool, epoch: UUID) throws -> Cursor {
        // Resolve a supplied path before taking the lock; never block another page
        // on a wide child search, and preserve the original path interpretation.
        let requestedRoot = try a["path"]?.string.map { try context.nodeID(path: $0) }
        lock.lock(); defer { lock.unlock() }
        try checkEpochLocked(epoch); expire(uptime: uptime())
        guard let cursor = entries[token] else { throw ControlError("stale_cursor", "Cursor expired, was consumed/cancelled or evicted; restart subtree pagination") }
        guard cursor.lease.context.revision == context.revision, cursor.lease.context.snapshot.nodes.sharesStorage(with: context.snapshot.nodes) else {
            cursor.control.cancel(); entries[token] = nil; if entries.isEmpty { lease = nil }
            throw ControlError("stale_revision", "Snapshot changed; restart subtree pagination")
        }
        guard requestedRoot == nil || requestedRoot == cursor.root, a["expression"] == nil || a["expression"]?.string == cursor.expression.text else {
            throw ControlError("invalid_argument", "Cursor scope and expression cannot change")
        }
        if cancel { cursor.control.cancel(); entries[token] = nil; cancelled += 1; if entries.isEmpty { lease = nil }; return cursor }
        guard !cursor.busy else { throw ControlError("busy", "This cursor already has an active page") }
        guard activePages < maximumCursors else { throw ControlError("busy", "All subtree page slots are active") }
        cursor.busy = true; activePages += 1; return cursor
    }
    private func commit(_ cursor: Cursor) throws -> String? {
        lock.lock(); defer { lock.unlock() }
        guard entries[cursor.token] === cursor, !cursor.control.isCancelled else { throw CancellationError() }
        entries[cursor.token] = nil; cursor.busy = false; activePages -= 1
        if !cursor.stack.isEmpty {
            cursor.token = UUID().uuidString; cursor.lastUsed = uptime()
            entries[cursor.token] = cursor; return cursor.token
        }
        if entries.isEmpty { lease = nil }; return nil
    }
    private func discard(_ cursor: Cursor) {
        lock.lock(); defer { lock.unlock() }
        cursor.control.cancel()
        if entries[cursor.token] === cursor { entries[cursor.token] = nil }
        if cursor.busy { cursor.busy = false; activePages -= 1 }
        if entries.isEmpty { lease = nil }
    }
}

/// Detached read work must inherit cancellation explicitly. Awaiting .value alone
/// does not cancel an unstructured child when its parent request is cancelled.
public enum QueryExecution {
    public static func run(_ operation: @escaping @Sendable () throws -> JSONValue) async throws -> JSONValue {
        let worker = Task.detached(priority: .utility) { try Task.checkCancellation(); return try operation() }
        return try await withTaskCancellationHandler(operation: { try await worker.value }, onCancel: { worker.cancel() })
    }
}
