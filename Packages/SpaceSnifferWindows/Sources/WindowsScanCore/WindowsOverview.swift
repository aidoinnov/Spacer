import SpaceSnifferScanEngine

/// Current-scan root candidates. Keep independent bounded rankings for each
/// size mode and item kind; files must not evict folders from the overview.
struct WindowsOverview {
    private struct Candidates {
        var ids: [Int] = []
        mutating func observe(_ id: Int, nodes: [WindowsNode], logical: Bool) {
            guard !ids.contains(id) else { return }
            func bytes(_ id: Int) -> UInt64 { logical ? nodes[id].logical : nodes[id].allocated }
            guard bytes(id) > 0 else { return }
            if ids.count < ScanOverviewPolicy.candidateLimit { ids.append(id); return }
            let least = ids.indices.min {
                bytes(ids[$0]) == bytes(ids[$1]) ? ids[$0] > ids[$1] : bytes(ids[$0]) < bytes(ids[$1])
            }!
            if bytes(id) > bytes(ids[least]) || (bytes(id) == bytes(ids[least]) && id < ids[least]) { ids[least] = id }
        }
    }
    private(set) var rootFolderCount = 0
    private var allocatedFolders = Candidates()
    private var logicalFolders = Candidates()
    private var allocatedFiles = Candidates()
    private var logicalFiles = Candidates()
    mutating func observe(_ id: Int, nodes: [WindowsNode], isNewRoot: Bool = false) {
        guard id > 0 else { return }
        if isNewRoot && nodes[id].directory { rootFolderCount += 1 }
        if nodes[id].directory {
            allocatedFolders.observe(id, nodes: nodes, logical: false)
            logicalFolders.observe(id, nodes: nodes, logical: true)
        } else {
            allocatedFiles.observe(id, nodes: nodes, logical: false)
            logicalFiles.observe(id, nodes: nodes, logical: true)
        }
    }
    func roots(_ nodes: [WindowsNode]) -> [WindowsOverviewEntry] {
        var seen = Set<Int>()
        return (allocatedFolders.ids + logicalFolders.ids + allocatedFiles.ids + logicalFiles.ids)
            .filter { seen.insert($0).inserted }
            .sorted { nodes[$0].allocated == nodes[$1].allocated ? $0 < $1 : nodes[$0].allocated > nodes[$1].allocated }
            .map { WindowsOverviewEntry(nodes[$0]) }
    }
}
