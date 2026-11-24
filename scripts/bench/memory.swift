import Foundation

/// Synthetic metadata only: no user files are scanned or created.
@main enum MemoryBenchmark {
    static func main() throws {
        let count = Int(CommandLine.arguments.dropFirst().first ?? "250000")!
        let scenario = CommandLine.arguments.dropFirst(2).first ?? "projection"
        precondition(count > 0)
        var snapshot = ScanSnapshot(rootPath: "/memory")
        snapshot.nodes.reserveCapacity(count + 2)
        snapshot.nodes.append(DiskNode(id: 0, parent: nil, path: "/memory", name: "memory", isDirectory: true,
            logicalBytes: Int64(count), allocatedBytes: Int64(count), children: Array(1...count)))
        for id in 1...count {
            var node = DiskNode(id: id, parent: 0, path: "/memory/file-\(id).bin", name: "file-\(id).bin", logicalBytes: 1, allocatedBytes: 1)
            node.fileIdentity = "1:\(id)"; snapshot.nodes.append(node)
        }
        snapshot.fileCount = count; snapshot.folderCount = 1
        let start = Date()
        var checksum: Int64 = 0
        switch scenario {
        case "projection":
            let projection = FilterProjection(snapshot: snapshot, filter: try ScanFilter(""), mode: .logical,
                showHidden: true, focusPath: snapshot.rootPath, selectionPath: nil, previous: snapshot,
                history: [snapshot.rootPath], historyIndex: 0, control: ScanControl())!
            precondition(projection.weights[0] == count && projection.children.count == count)
            checksum = projection.weights[0]
            withExtendedLifetime(projection) {}
        case "snapshot":
            let frozen = snapshot
            snapshot.nodes[0].logicalBytes += 1
            snapshot.nodes[count].allocatedBytes = 2
            snapshot.nodes.append(DiskNode(id: count + 1, parent: 0, path: "/memory/new.bin", name: "new.bin", logicalBytes: 1))
            snapshot.nodes[0].children.append(count + 1)
            precondition(frozen.nodes[0].logicalBytes == count && frozen.nodes[count].allocatedBytes == 1)
            checksum = snapshot.nodes[0].logicalBytes
            withExtendedLifetime((frozen, snapshot)) {}
        case "merge":
            let node = DiskNode(id: 0, parent: nil, path: "/memory/file-1.bin", name: "file-1.bin", logicalBytes: 2, allocatedBytes: 2)
            let subtree = ScanSnapshot(rootPath: node.path, nodes: [node])
            let result = SnapshotTree.replacing(snapshot, with: subtree, control: ScanControl())!
            precondition(result.nodes[0].logicalBytes == count + 1 && snapshot.nodes[0].logicalBytes == count)
            checksum = result.nodes[0].logicalBytes
            withExtendedLifetime((result, snapshot)) {}
        default: fatalError("scenario must be projection, snapshot, or merge")
        }
        let output: [String: Any] = ["scenario": scenario, "files": count, "seconds": Date().timeIntervalSince(start),
            "checksum": checksum, "nodeStride": MemoryLayout<DiskNode>.stride]
        print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), as: UTF8.self))
    }
}
