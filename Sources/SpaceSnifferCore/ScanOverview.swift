import Foundation

/// Observations from this scan only. A folder value is its observed descendant
/// sum, never an estimate of unvisited space or reclaimable disk capacity.
public struct ScanOverviewItem: Sendable, Codable, Identifiable, Equatable {
    public let id: Int
    public let path: String
    public let name: String
    public let allocatedBytes: Int64
    public let logicalBytes: Int64
}

public struct ScanOverview: Sendable, Codable, Equatable {
    public let folders: [ScanOverviewItem]
    public let largeFiles: [ScanOverviewItem]
    public var observedNodeCount: Int = 0
}

/// Only bounded value copies cross into progress. No NodeTable, cache, worker,
/// second filesystem pass or per-file retained dictionary belongs here.
struct ScanOverviewAccumulator {
    private struct Top {
        var items: [ScanOverviewItem] = []
        private var cutoffBytes: Int64 = 0
        private var cutoffID: Int = .max
        mutating func offer(_ node: DiskNode) {
            offer(id: node.id, path: node.path, name: node.name, allocated: node.allocatedBytes, logical: node.logicalBytes)
        }
        mutating func offer(id: Int, path: String, name: String, allocated: Int64, logical: Int64) {
            guard allocated > 0 else { return }
            if allocated < cutoffBytes || (allocated == cutoffBytes && id > cutoffID) { return }
            if let index = items.firstIndex(where: { $0.id == id }) {
                guard items[index].allocatedBytes != allocated || items[index].logicalBytes != logical else { return }
                items.remove(at: index)
            }
            var low = 0, high = items.count
            while low < high {
                let middle = (low + high) / 2
                if items[middle].allocatedBytes > allocated || (items[middle].allocatedBytes == allocated && items[middle].id < id) { low = middle + 1 }
                else { high = middle }
            }
            items.insert(ScanOverviewItem(id: id, path: path, name: name, allocatedBytes: allocated, logicalBytes: logical), at: low)
            if items.count > 16 { items.removeLast() }
            if items.count == 16, let last = items.last { cutoffBytes = last.allocatedBytes; cutoffID = last.id }
        }
    }
    private var folders = Top()
    private var files = Top()
    private var cursor = 0
    private var publication = ScanPublication()
    mutating func observeFolder(_ node: DiskNode) { folders.offer(node) }
    mutating func observeFile(_ node: DiskNode) { files.offer(node) }
    mutating func update(from snapshot: ScanSnapshot, force: Bool = false) {
        guard force || publication.shouldPublish(nodeCount: snapshot.nodes.count) else { return }
        precondition(snapshot.nodes.count >= cursor)
        for index in cursor..<snapshot.nodes.count {
            let node = snapshot.nodes[index]
            if !node.isDirectory { files.offer(node) }
        }
        if let root = snapshot.nodes.first {
            for id in root.children {
                let node = snapshot.nodes[id]
                if node.isDirectory { folders.offer(node) }
            }
        }
        cursor = snapshot.nodes.count
    }
    var value: ScanOverview { ScanOverview(folders: folders.items, largeFiles: files.items, observedNodeCount: cursor) }
}
