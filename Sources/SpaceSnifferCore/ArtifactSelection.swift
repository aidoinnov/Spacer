import Foundation

/// One timestamp and one leaf evaluation. Ancestor propagation happens only after
/// weights are calculated, so folder inclusion cannot count a file twice.
enum ArtifactSelection {
    static func snapshot(_ snapshot: ScanSnapshot, filter: ScanFilter, showHidden: Bool, now: Date) -> [Bool] {
        var selected = filter.membership(in: snapshot, showHidden: showHidden, now: now) ?? []
        includeAncestors(&selected, snapshot: snapshot)
        return selected
    }
    static func report(_ snapshot: ScanSnapshot, filter: ScanFilter, mode: SizeMode, showHidden: Bool, now: Date) -> (selected: [Bool], weights: [Int64]) {
        var selected = filter.membership(in: snapshot, showHidden: showHidden, now: now) ?? []
        let weights = filter.weights(in: snapshot, mode: mode, included: selected)
        includeAncestors(&selected, snapshot: snapshot)
        return (selected, weights)
    }
    private static func includeAncestors(_ selected: inout [Bool], snapshot: ScanSnapshot) {
        guard selected.count > 1 else { return }
        for id in stride(from: selected.count - 1, through: 1, by: -1) {
            if selected[id], let parent = snapshot.nodes[id].parent { selected[parent] = true }
        }
    }
}

/// Immutable, source-bound selection for clients that need both an output and a
/// summary (CLI). It prevents a second filter pass and a second timestamp.
public struct ArtifactProjection: Sendable {
    let snapshot: ScanSnapshot
    let root: Int
    let selected: [Bool]
    let weights: [Int64]
    public var matchedBytes: Int64 { weights.indices.contains(root) ? weights[root] : 0 }
    public init(_ snapshot: ScanSnapshot, filter: ScanFilter, mode: SizeMode, showHidden: Bool, root: Int = 0, now: Date = Date()) {
        self.snapshot = snapshot; self.root = root
        let result = ArtifactSelection.report(snapshot, filter: filter, mode: mode, showHidden: showHidden, now: now)
        selected = result.selected; weights = result.weights
    }
}
