import Foundation
@testable import SpaceSnifferCore

// Frozen pre-bitset implementation. Independent Set storage and original guards.
extension ScanSnapshot {
    func frozenSetValidated() throws -> Self {
        guard version == 1, !nodes.isEmpty, nodes[0].parent == nil, nodes[0].path == rootPath,
              tags.values.allSatisfy({ (1...15).contains($0) }),
              volumeTotal >= 0, volumeFree >= 0, fileCount >= 0, folderCount >= 0, issueCount >= 0 else { throw SnapshotError.invalid }
        var incoming = Set<Int>()
        for (i, node) in nodes.enumerated() {
            guard node.id == i, node.logicalBytes >= 0, node.allocatedBytes >= 0,
                  (node.ownAllocatedBytes ?? 0) >= 0, SnapshotPath.isAbsolute(node.path), node.children.count <= nodes.count else { throw SnapshotError.invalid }
            if i > 0 {
                guard let parent = node.parent, parent >= 0, parent < i else { throw SnapshotError.invalid }
                let expected = SnapshotPath.join(nodes[parent].path, node.name)
                guard node.name != ".", node.name != "..", !node.name.contains("/"), (!SnapshotPath.isWindows(nodes[parent].path) || !node.name.contains("\\")), node.path == expected else { throw SnapshotError.invalid }
            }
            var logicalSum: Int64 = 0; var allocatedSum: Int64 = 0
            for child in node.children {
                guard child > i, child < nodes.count, nodes[child].parent == i,
                      incoming.insert(child).inserted else { throw SnapshotError.invalid }
                let l = logicalSum.addingReportingOverflow(nodes[child].logicalBytes)
                let a = allocatedSum.addingReportingOverflow(nodes[child].allocatedBytes)
                guard !l.overflow, !a.overflow else { throw SnapshotError.invalid }
                logicalSum = l.partialValue; allocatedSum = a.partialValue
            }
            guard node.isDirectory || node.children.isEmpty,
                  node.logicalBytes >= logicalSum, node.allocatedBytes >= allocatedSum else { throw SnapshotError.invalid }
        }
        guard incoming.count == nodes.count - 1 else { throw SnapshotError.invalid }
        return self
    }
}
