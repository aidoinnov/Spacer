import Foundation
import CoreGraphics

/// An immutable, opaque provenance boundary. Callers cannot reuse an identity
/// while replacing its snapshot/weights. Public construction always gets a new key.
public final class GeometrySource: Sendable {
    public let snapshot: ScanSnapshot
    public let weights: [Int64]
    let identity: UUID
    public init(snapshot: ScanSnapshot, weights: [Int64]) { self.snapshot = snapshot; self.weights = weights; identity = UUID() }
    init(snapshot: ScanSnapshot, weights: [Int64], identity: UUID) { self.snapshot = snapshot; self.weights = weights; self.identity = identity }
}

public struct GeometryStatistics: Sendable {
    public var sorts = 0
    public var sortHits = 0
    public var rectHits = 0
    public var retainedSortItems = 0
    public var retainedTiles = 0
}

/// Per-window cache; immutable numbers/IDs only, never snapshots or GeometrySource.
/// Brief locks protect capture/commit/reset. Layout never runs while holding a lock.
public final class GeometrySession: @unchecked Sendable {
    private struct SortKey: Hashable { let source: UUID; let parent: Int }
    private struct SortEntry { let children: [Int]; let values: [(Int, Double)] }
    private struct RectKey: Equatable {
        let source: UUID; let root: Int; let depth: Int; let selected: Int?
        let bounds: CGRect
        // version 1 is the unchanged Double comparator and squarify policy.
    }
    private struct State {
        var sorted: [SortKey: SortEntry] = [:]
        var previousUsed: Set<SortKey> = []
        var rectangles: [(RectKey, [TreemapTile])] = []
    }
    private let lock = NSLock()
    private var state = State()
    private var generation = UUID()
    private var metrics = GeometryStatistics()
    private let sortItemLimit: Int
    private let tileLimit: Int
    public init(sortItemLimit: Int = 65_536, tileLimit: Int = 50_000) {
        self.sortItemLimit = max(0, sortItemLimit); self.tileLimit = max(0, tileLimit)
    }
    public func reset() {
        lock.lock(); generation = UUID(); state = State(); metrics.retainedSortItems = 0; metrics.retainedTiles = 0; lock.unlock()
    }
    public func statistics() -> GeometryStatistics { lock.lock(); defer { lock.unlock() }; return metrics }
    public func tiles(source: GeometrySource, root: Int, depth: Int, selected: Int?, in bounds: CGRect, control: ScanControl) -> [TreemapTile]? {
        let started = DispatchTime.now().uptimeNanoseconds
        defer { WorkerTelemetry.shared.observe("geometry.session", nanoseconds: DispatchTime.now().uptimeNanoseconds &- started) }
        guard !control.isCancelled else { return nil }
        lock.lock(); var working = state; let token = generation; lock.unlock()
        let key = RectKey(source: source.identity, root: root, depth: depth, selected: selected, bounds: bounds)
        if let hit = working.rectangles.first(where: { $0.0 == key }) {
            lock.lock()
            if generation == token {
                metrics.rectHits += 1
                if let index = state.rectangles.firstIndex(where: { $0.0 == key }) {
                    let entry = state.rectangles.remove(at: index); state.rectangles.insert(entry, at: 0)
                }
            }
            lock.unlock()
            WorkerTelemetry.shared.record("geometry.rect_cache_hit")
            return control.isCancelled ? nil : hit.1
        }
        var sorts = 0; var hits = 0; var used = Set<SortKey>()
        var retained = working.sorted.values.reduce(0) { $0 + $1.values.count + $1.children.count }
        let getSorted: (Int, [Int]) -> [(Int, Double)] = { parent, children in
                let key = SortKey(source: source.identity, parent: parent); used.insert(key)
                if let cached = working.sorted[key], cached.children == children { hits += 1; return cached.values }
                sorts += 1
                var values: [(Int, Double)] = []
                for child in children {
                    let weight = Double(source.weights[child])
                    if weight > 0 && weight.isFinite { values.append((child, weight)) }
                }
                WorkerTelemetry.shared.measure("geometry.sort") {
                    values.sort { (lhs: (Int, Double), rhs: (Int, Double)) in
                        lhs.1 == rhs.1 ? lhs.0 < rhs.0 : lhs.1 > rhs.1
                    }
                }
                let slots = children.count + values.count
                if slots <= self.sortItemLimit - retained, working.sorted.count < 128 {
                    working.sorted[key] = SortEntry(children: children, values: values); retained += slots
                }
                return values
            }
        let result = WorkerTelemetry.shared.measure("geometry.layout") { Treemap.tilesImpl(snapshot: source.snapshot, weights: source.weights, root: root, depth: depth, selected: selected,
            in: bounds, control: control, sorted: getSorted) }
        guard let result, !control.isCancelled else { return nil }
        let keep = used.union(working.previousUsed)
        working.sorted = working.sorted.filter { keep.contains($0.key) }; working.previousUsed = used
        working.rectangles.removeAll { $0.0 == key }
        if result.count <= tileLimit {
            working.rectangles.insert((key, result), at: 0)
            while working.rectangles.count > 2 || working.rectangles.reduce(0, { $0 + $1.1.count }) > tileLimit { working.rectangles.removeLast() }
        }
        lock.lock()
        if generation == token {
            state = working; metrics.sorts += sorts; metrics.sortHits += hits
            metrics.retainedSortItems = working.sorted.values.reduce(0) { $0 + $1.values.count + $1.children.count }
            metrics.retainedTiles = working.rectangles.reduce(0) { $0 + $1.1.count }
        }
        lock.unlock()
        return result
    }
}
