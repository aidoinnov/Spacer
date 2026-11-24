import Foundation

/// Construct a new source for every snapshot/metadata/tag change. Copies retain the
/// same identity for navigation. A caller cannot attach an old identity to new data.
public struct ProjectionSource: Sendable {
    public let snapshot: ScanSnapshot
    let identity = UUID()
    public init(_ snapshot: ScanSnapshot) { self.snapshot = snapshot }
}

public struct ProjectionRequest: Sendable {
    public let source: ProjectionSource
    public let filterText: String
    public let fallbackFilter: ScanFilter
    public let mode: SizeMode
    public let showHidden: Bool
    public let focusPath: String?
    public let selectionPath: String?
    public let previous: ScanSnapshot?
    public let history: [String]
    public let historyIndex: Int
    public init(source: ProjectionSource, filterText: String, fallbackFilter: ScanFilter,
                mode: SizeMode, showHidden: Bool, focusPath: String?, selectionPath: String?,
                previous: ScanSnapshot? = nil, history: [String] = [], historyIndex: Int = -1) {
        self.source = source; self.filterText = filterText; self.fallbackFilter = fallbackFilter
        self.mode = mode; self.showHidden = showHidden; self.focusPath = focusPath
        self.selectionPath = selectionPath; self.previous = previous
        self.history = history; self.historyIndex = historyIndex
    }
}

public struct ProjectionOutcome: Sendable {
    public let projection: FilterProjection
    public let filter: ScanFilter
    public let error: String?
    public let requestedSelectionPath: String?
    public let reusedEvaluation: Bool
    public let evaluationKind: ProjectionEvaluationKind
}
public enum ProjectionEvaluationKind: String, Sendable { case full, reused, incremental }

/// Window-local ownership of one cached evaluation and one latest-only worker.
/// Cache is committed only for the current request on MainActor; worker code only
/// reads immutable captured values. It never mutates a reader's arrays in place.
@MainActor
public final class ProjectionSession {
    private struct Key: Equatable, Sendable {
        let source: UUID
        let filter: String
        let mode: SizeMode
        let showHidden: Bool
    }
    private struct Cache: Sendable {
        let key: Key
        let evaluation: ProjectionEvaluation
        let source: ProjectionSource
        let lookup: [String: Int]
        let filter: ScanFilter
        let orders: [ProjectionChildOrder]
    }
    private struct Completed: Sendable {
        let outcome: ProjectionOutcome
        let cache: Cache?
    }
    private let worker = LatestWorker<Completed>(name: "filter.projection")
    private var cache: Cache?
    private var scratch = FilterScratch()
    private var generation = UUID()
    private var stopped = false
    public init() {}

    public func submit(_ request: ProjectionRequest, completion: @escaping @MainActor @Sendable (ProjectionOutcome) -> Void) {
        guard !stopped else { return }
        let token = UUID(); generation = token
        let candidate = cache
        let scratch = scratch
        worker.submit(operation: { control in
            let parsed: ScanFilter; let error: String?
            do {
                if let candidate, candidate.filter.text == request.filterText { parsed = candidate.filter }
                else { WorkerTelemetry.shared.record("filter.parse"); parsed = try ScanFilter(request.filterText) }
                error = nil
            }
            catch let failure { parsed = request.fallbackFilter; error = failure.localizedDescription }
            let key = Key(source: request.source.identity, filter: parsed.text, mode: request.mode, showHidden: request.showHidden)
            let sameNodes = candidate.map { $0.source.snapshot.rootPath == request.source.snapshot.rootPath && $0.source.snapshot.nodes.sharesStorage(with: request.source.snapshot.nodes) } ?? false
            let sameEvaluation = candidate.map { $0.key.filter == key.filter && $0.key.mode == key.mode && $0.key.showHidden == key.showHidden &&
                (!parsed.isTagDependent || $0.source.snapshot.tags == request.source.snapshot.tags) } ?? false
            let reuse = !parsed.isTimeDependent && (candidate?.key == key || sameNodes && sameEvaluation)
            let evaluation: ProjectionEvaluation
            let kind: ProjectionEvaluationKind
            var stableIDs = sameNodes
            if reuse, let candidate { evaluation = candidate.evaluation; kind = .reused }
            else if !parsed.isTimeDependent, sameEvaluation, let candidate,
                    let delta = ProjectionDelta(baseline: candidate.source, result: request.source, control: control),
                    let calculated = delta.apply(previous: candidate.evaluation, baseline: candidate.source, result: request.source,
                        filter: parsed, mode: request.mode, showHidden: request.showHidden, control: control) {
                evaluation = calculated; stableIDs = true
                kind = calculated.identity == candidate.evaluation.identity ? .reused : .incremental
            }
            else {
                WorkerTelemetry.shared.record("filter.membership")
                guard let calculated = ProjectionEvaluation(snapshot: request.source.snapshot, filter: parsed,
                    mode: request.mode, showHidden: request.showHidden, control: control, scratch: scratch) else { return nil }
                evaluation = calculated
                kind = .full
            }
            if kind == .reused { WorkerTelemetry.shared.record("filter.reuse") }
            if kind == .incremental { WorkerTelemetry.shared.record("filter.delta") }
            guard let projection = FilterProjection(snapshot: request.source.snapshot, evaluation: evaluation,
                focusPath: request.focusPath, selectionPath: request.selectionPath, previous: request.previous,
                history: request.history, historyIndex: request.historyIndex, control: control, lookup: stableIDs ? candidate?.lookup ?? [:] : [:],
                childOrders: stableIDs && evaluation.identity == candidate?.evaluation.identity ? candidate?.orders ?? [] : []) else { return nil }
            let outcome = ProjectionOutcome(projection: projection, filter: parsed, error: error,
                requestedSelectionPath: request.selectionPath, reusedEvaluation: kind == .reused, evaluationKind: kind)
            return Completed(outcome: outcome, cache: Cache(key: key, evaluation: evaluation, source: request.source, lookup: projection.trackedLookup, filter: parsed, orders: projection.childOrders))
        }, completion: { [weak self] completed in
            Task { @MainActor [weak self] in
                guard let self, !self.stopped, self.generation == token else { WorkerTelemetry.shared.note("filter.projection", stale: 1); return }
                self.cache = completed.cache
                WorkerTelemetry.shared.record("filter.publish")
                completion(completed.outcome)
            }
        })
    }

    /// Drop cache immediately on root/load/disconnect; an in-flight reader keeps
    /// only its own immutable copy until cooperative cancellation completes.
    public func reset() { generation = UUID(); worker.cancel(); cache = nil; scratch = FilterScratch() }
    public func shutdown() { stopped = true; reset(); worker.shutdown() }
}
