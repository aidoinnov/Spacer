import Foundation

/// Pure projection calculation, independent of scheduling, cache lifetime and UI publication.
/// W02: setNewFocus 0x428bb0 reuses the filtered tree for navigation.
struct ProjectionEvaluation: Sendable {
    let identity = UUID()
    let included: [Bool]
    let weights: [Int64]
    init(included: [Bool], weights: [Int64]) { self.included = included; self.weights = weights }
    init?(snapshot: ScanSnapshot, filter: ScanFilter, mode: SizeMode, showHidden: Bool, control: ScanControl, scratch: FilterScratch? = nil) {
        let membership: [Bool]?
        if let scratch { membership = scratch.membership(filter: filter, snapshot: snapshot, showHidden: showHidden, control: control) }
        else { membership = filter.membership(in: snapshot, showHidden: showHidden, control: control) }
        guard let included = membership else { return nil }
        let weights = filter.weights(in: snapshot, mode: mode, included: included, control: control)
        guard !control.isCancelled else { return nil }
        self.included = included; self.weights = weights
    }
}

struct ProjectionChildOrder: Sendable {
    let parent: Int; let children: [Int]; let order: [Int]
}
public struct FilterProjection: Sendable {
    let childOrders: [ProjectionChildOrder]
    public let geometrySource: GeometrySource
    let trackedLookup: [String: Int]
    public var trackedNodeIDs: [String: Int] { trackedLookup }
    public let snapshot: ScanSnapshot
    public let weights: [Int64]
    public let focus: Int
    public let selection: Int?
    public let children: [Int]
    public let history: [String]
    public let historyIndex: Int
    public init?(snapshot: ScanSnapshot, filter: ScanFilter, mode: SizeMode, showHidden: Bool,
                 focusPath: String?, selectionPath: String?, previous: ScanSnapshot? = nil,
                 history: [String] = [], historyIndex: Int = -1, control: ScanControl) {
        guard let evaluation = ProjectionEvaluation(snapshot: snapshot, filter: filter, mode: mode, showHidden: showHidden, control: control) else { return nil }
        self.init(snapshot: snapshot, evaluation: evaluation, focusPath: focusPath, selectionPath: selectionPath,
                  previous: previous, history: history, historyIndex: historyIndex, control: control)
    }
    init?(snapshot: ScanSnapshot, evaluation: ProjectionEvaluation, focusPath: String?, selectionPath: String?,
          previous: ScanSnapshot?, history: [String], historyIndex: Int, control: ScanControl, lookup: [String: Int] = [:], childOrders: [ProjectionChildOrder] = []) {
        guard !control.isCancelled else { return nil }
        let included = evaluation.included; let values = evaluation.weights
        geometrySource = GeometrySource(snapshot: snapshot, weights: values, identity: evaluation.identity)
        guard let navigation = NavigationState(snapshot: snapshot, previous: previous, included: included, weights: values,
            focusPath: focusPath, selectionPath: selectionPath, history: history, historyIndex: historyIndex, control: control, lookup: lookup) else { return nil }
        trackedLookup = navigation.trackedLookup
        self.snapshot = snapshot; self.weights = values
        let focus = navigation.focus
        self.focus = focus; self.selection = navigation.selection
        self.history = navigation.history; self.historyIndex = navigation.historyIndex
        let sourceChildren = snapshot.nodes.indices.contains(focus) ? snapshot.nodes[focus].children : []
        if let cached = childOrders.first(where: { $0.parent == focus && $0.children == sourceChildren }) {
            children = cached.order; WorkerTelemetry.shared.record("filter.children_sort_hit")
        } else {
            children = WorkerTelemetry.shared.measure("filter.children_sort") { sourceChildren.filter { values[$0] > 0 }.sorted {
                values[$0] == values[$1] ? $0 < $1 : values[$0] > values[$1]
            } }
        }
        var orders = [ProjectionChildOrder(parent: focus, children: sourceChildren, order: children)]
        orders.append(contentsOf: childOrders.filter { $0.parent != focus }.prefix(1))
        while orders.reduce(0, { $0 + $1.children.count + $1.order.count }) > 65_536 { orders.removeLast() }
        self.childOrders = orders
    }
}
