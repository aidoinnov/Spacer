import Foundation

@main enum ArtifactPoolMemoryProbe {
    static func fixture(_ count: Int) -> ScanSnapshot {
        let base = "/probe/" + String(repeating: "long-parent-component-", count: 7)
        var snapshot = ScanSnapshot(rootPath: base)
        snapshot.nodes.append(DiskNode(id: 0, parent: nil, path: base, name: "probe", isDirectory: true))
        for branch in 0..<100 {
            let parent = snapshot.nodes.count, folder = base + "/branch-\(branch)"
            snapshot.nodes.append(DiskNode(id: parent, parent: 0, path: folder, name: "branch-\(branch)", isDirectory: true))
            snapshot.nodes[0].children.append(parent)
            for index in 0..<(count / 100 + (branch < count % 100 ? 1 : 0)) {
                let name = "한글-file-\(index).bin", id = snapshot.nodes.count
                snapshot.nodes.append(DiskNode(id: id, parent: parent, path: folder + "/" + name, name: name, logicalBytes: 1234, allocatedBytes: 4096))
                snapshot.nodes[parent].children.append(id)
                snapshot.nodes[parent].logicalBytes += 1234; snapshot.nodes[parent].allocatedBytes += 4096
            }
            snapshot.nodes[0].logicalBytes += snapshot.nodes[parent].logicalBytes
            snapshot.nodes[0].allocatedBytes += snapshot.nodes[parent].allocatedBytes
        }
        snapshot.fileCount = count; snapshot.folderCount = 101
        return snapshot
    }
    static func main() throws {
        let mode = CommandLine.arguments[1], count = Int(CommandLine.arguments[2])!
        let snapshot = fixture(count)
        var seconds = 0.0
        if mode != "input" {
            let transaction = try ArtifactFileTransaction(to: URL(fileURLWithPath: CommandLine.arguments[3]), replaceExisting: false)
            var sink = ArtifactFileSink(transaction)
            let start = DispatchTime.now().uptimeNanoseconds
            if mode == "legacy" { try LegacySNSSnapshot.write(snapshot, to: &sink) }
            else { try SNSSnapshot.write(snapshot, to: &sink) }
            try sink.finish()
            seconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: ["mode":mode,"files":count,"nodes":snapshot.nodes.count,"seconds":seconds],options:[.sortedKeys]),as:UTF8.self))
    }
}
