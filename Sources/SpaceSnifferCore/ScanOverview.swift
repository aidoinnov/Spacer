import Foundation
import SpaceSnifferScanEngine

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
    public static let wireVersion = ScanOverviewPolicy.wireVersion
    public let folders: [ScanOverviewItem]
    public let largeFiles: [ScanOverviewItem]
    public var observedNodeCount: Int = 0
    public var rootFolderCount: Int? = nil
    public var logicalFolders: [ScanOverviewItem]? = nil
    public var logicalLargeFiles: [ScanOverviewItem]? = nil
}

/// Only bounded value copies cross into progress. No NodeTable, cache, worker,
/// second filesystem pass or per-file retained dictionary belongs here.
struct ScanOverviewAccumulator {
    private struct Top {
        var items: [ScanOverviewItem] = []
        let logical: Bool
        init(logical: Bool = false) { self.logical = logical }
        private func weight(_ item: ScanOverviewItem) -> Int64 { logical ? item.logicalBytes : item.allocatedBytes }
        private var cutoffBytes: Int64 = 0
        private var cutoffID: Int = .max
        mutating func offer(_ node: DiskNode) {
            let id = node.id, allocated = node.allocatedBytes, logical = node.logicalBytes
            let bytes = self.logical ? logical : allocated
            guard bytes > 0 else { return }
            if bytes < cutoffBytes || (bytes == cutoffBytes && id > cutoffID) { return }
            if let index = items.firstIndex(where: { $0.id == id }) {
                guard items[index].allocatedBytes != allocated || items[index].logicalBytes != logical else { return }
                items.remove(at: index)
            }
            var low = 0, high = items.count
            while low < high {
                let middle = (low + high) / 2
                if weight(items[middle]) > bytes || (weight(items[middle]) == bytes && items[middle].id < id) { low = middle + 1 }
                else { high = middle }
            }
            // Materialize paths only after admission; most files miss the bounded rankings.
            items.insert(ScanOverviewItem(id: id, path: node.path, name: node.name, allocatedBytes: allocated, logicalBytes: logical), at: low)
            if items.count > ScanOverviewPolicy.candidateLimit { items.removeLast() }
            if items.count == ScanOverviewPolicy.candidateLimit, let last = items.last { cutoffBytes = weight(last); cutoffID = last.id }
        }
    }
    private var folders = Top()
    private var files = Top()
    private var logicalFolders = Top(logical: true)
    private var logicalFiles = Top(logical: true)
    private var cursor = 0
    private var rootFolderCount = 0
    private var dirtyRoots = Set<Int>()
    private(set) var refreshedFolderCount = 0
    // The builder knows the current root branch; no per-file ancestor walks.
    mutating func markRootChanged(_ id: Int) { if id > 0 { dirtyRoots.insert(id) } }
    mutating func observeFolder(_ node: DiskNode) { folders.offer(node); logicalFolders.offer(node) }
    mutating func observeFile(_ node: DiskNode) { files.offer(node); logicalFiles.offer(node) }
    mutating func update(from snapshot: ScanSnapshot) {
        // Called at the scanner's existing heartbeat boundary, after ancestor
        // deltas are flushed. Full snapshot publication has a separate throttle.
        precondition(snapshot.nodes.count >= cursor)
        refreshedFolderCount = 0
        for index in cursor..<snapshot.nodes.count {
            let node = snapshot.nodes[index]
            if !node.isDirectory { observeFile(node) }
            else if node.parent == 0 {
                rootFolderCount += 1
                observeFolder(node)
                refreshedFolderCount += 1
                dirtyRoots.remove(node.id)
            }
        }
        for id in dirtyRoots {
            observeFolder(snapshot.nodes[id])
            refreshedFolderCount += 1
        }
        dirtyRoots.removeAll(keepingCapacity: true)
        cursor = snapshot.nodes.count
    }
    var value: ScanOverview { ScanOverview(folders: folders.items, largeFiles: files.items, observedNodeCount: cursor, rootFolderCount: rootFolderCount,
        logicalFolders: logicalFolders.items, logicalLargeFiles: logicalFiles.items) }
}
