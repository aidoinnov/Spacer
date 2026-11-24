/// Bounded current-scan root buckets. Totals only grow during enumeration;
/// retaining 16 IDs avoids sorting every root entry for each heartbeat.
struct WindowsOverview {
    private var ids: [Int] = []
    mutating func observe(_ id: Int, nodes: [WindowsNode]) {
        guard id > 0, !ids.contains(id) else { return }
        if ids.count < 16 { ids.append(id); return }
        let least = ids.indices.min { nodes[ids[$0]].allocated < nodes[ids[$1]].allocated }!
        if nodes[id].allocated > nodes[ids[least]].allocated { ids[least] = id }
    }
    func roots(_ nodes: [WindowsNode]) -> [WindowsOverviewEntry] {
        ids.map { nodes[$0] }.sorted { $0.allocated > $1.allocated }.map(WindowsOverviewEntry.init)
    }
}
