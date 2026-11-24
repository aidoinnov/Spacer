import Foundation

private actor LegacyArtifactWorker {
    func export(_ snapshot: ScanSnapshot, filter: ScanFilter, format: String, root: Int, to output: URL) throws {
        let ids = filter.matchingIDs(in: snapshot, showHidden: true, root: root)
        let data: Data
        if format == "sns" { data = try LegacyArtifactReference.encode(snapshot, ids: Set(ids), root: root) }
        else {
            let weights = filter.weights(in: snapshot, mode: .logical, showHidden: true)
            data = Data(LegacyArtifactReference.simpleFileList(snapshot, ids: Set(ids), weights: weights, root: root).utf8)
        }
        try data.write(to: output, options: .atomic)
    }
}
@main enum ArtifactExportBenchmark {
    @MainActor static func main() async throws {
        let mode = CommandLine.arguments[1]; let format = CommandLine.arguments[2]; let scope = CommandLine.arguments[3]
        let output = URL(fileURLWithPath: CommandLine.arguments[4])
        let count = Int(CommandLine.arguments.dropFirst(5).first ?? "250000")!
        var s = ScanSnapshot(rootPath: "/artifact-audit")
        s.nodes.append(DiskNode(id: 0, parent: nil, path: s.rootPath, name: "artifact-audit", isDirectory: true))
        for branch in 0..<100 {
            let id = s.nodes.count; s.nodes[0].children.append(id)
            let path = "/artifact-audit/branch-\(branch)"
            s.nodes.append(DiskNode(id: id, parent: 0, path: path, name: "branch-\(branch)", isDirectory: true))
            for file in 0..<(count / 100) {
                let child = s.nodes.count; s.nodes[id].children.append(child)
                let name = "file-\(file)." + (file % 2 == 0 ? "bin" : "txt")
                let bytes = Int64(file % 101)
                s.nodes.append(DiskNode(id: child, parent: id, path: path + "/" + name, name: name, logicalBytes: bytes, allocatedBytes: bytes == 0 ? 0 : 4096))
                s.nodes[id].logicalBytes += bytes; s.nodes[id].allocatedBytes += bytes == 0 ? 0 : 4096
            }
            s.nodes[0].logicalBytes += s.nodes[id].logicalBytes; s.nodes[0].allocatedBytes += s.nodes[id].allocatedBytes
        }
        let filter = try ScanFilter("*.bin"); let root = scope == "all" ? 0 : 1
        let begin = ProcessInfo.processInfo.systemUptime
        if mode == "legacy" { try await LegacyArtifactWorker().export(s, filter: filter, format: format, root: root, to: output) }
        else if format == "sns" { try await ArtifactWorker().save(s, filter: filter, showHidden: true, root: root, to: output) }
        else { try await ArtifactWorker().export(s, filter: filter, mode: .logical, showHidden: true, root: root, to: output) }
        let seconds = ProcessInfo.processInfo.systemUptime - begin
        let bytes = (try FileManager.default.attributesOfItem(atPath: output.path)[.size] as! NSNumber).int64Value
        let record: [String: Any] = ["mode":mode,"format":format,"scope":scope,"files":count,"seconds":seconds,"bytes":bytes]
        print(String(decoding:try JSONSerialization.data(withJSONObject:record,options:.sortedKeys),as:UTF8.self))
    }
}
