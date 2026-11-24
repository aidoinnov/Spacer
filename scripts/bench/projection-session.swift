import Foundation

/// Metadata-only comparison of the old full-evaluation path and the production
/// session path, both through LatestWorker + MainActor completion. No disk scan/UI.
@main enum ProjectionSessionBenchmark {
    @MainActor static func main() async throws {
        let mode = CommandLine.arguments[1]
        let count = Int(CommandLine.arguments.dropFirst(2).first ?? "250000")!
        precondition(mode == "full" || mode == "session")
        var snapshot = ScanSnapshot(rootPath: "/audit")
        snapshot.nodes.append(DiskNode(id: 0, parent: nil, path: "/audit", name: "audit", isDirectory: true, children: []))
        for folder in 0..<100 {
            let id = snapshot.nodes.count; snapshot.nodes[0].children.append(id)
            let path = "/audit/branch-\(folder)"
            snapshot.nodes.append(DiskNode(id: id, parent: 0, path: path, name: "branch-\(folder)", isDirectory: true))
            for file in 0..<(count / 100) {
                let child = snapshot.nodes.count; snapshot.nodes[id].children.append(child)
                let name = "file-\(file)." + (file % 2 == 0 ? "bin" : "txt")
                snapshot.nodes.append(DiskNode(id: child, parent: id, path: path + "/" + name, name: name, logicalBytes: 1, allocatedBytes: 4096))
            }
        }
        let source = ProjectionSource(snapshot)
        let session = ProjectionSession(); defer { session.shutdown() }
        let worker = LatestWorker<FilterProjection>(); defer { worker.shutdown() }
        let fallback = try ScanFilter("")
        let frozen = snapshot
        func project(_ focus: String) async -> (FilterProjection, Bool) {
            if mode == "session" {
                return await withCheckedContinuation { continuation in
                    let request = ProjectionRequest(source: source, filterText: "*.bin", fallbackFilter: fallback, mode: .logical,
                        showHidden: true, focusPath: focus, selectionPath: nil, previous: frozen, history: ["/audit"], historyIndex: 0)
                    session.submit(request) { continuation.resume(returning: ($0.projection, $0.reusedEvaluation)) }
                }
            }
            return await withCheckedContinuation { continuation in
                worker.submit(operation: { control in
                    let filter = try! ScanFilter("*.bin")
                    return FilterProjection(snapshot: frozen, filter: filter, mode: .logical, showHidden: true,
                        focusPath: focus, selectionPath: nil, previous: frozen, history: ["/audit"], historyIndex: 0, control: control)
                }, completion: { result in
                    Task { @MainActor in continuation.resume(returning: (result, false)) }
                })
            }
        }
        let initialStart = ProcessInfo.processInfo.systemUptime
        let initial = await project("/audit")
        let initialSeconds = ProcessInfo.processInfo.systemUptime - initialStart
        precondition(initial.0.weights[0] == count / 2)
        let start = ProcessInfo.processInfo.systemUptime
        var checksum: Int64 = 0; var reuseCount = 0
        for i in 0..<10 {
            let (result, reused) = await project("/audit/branch-\(i)")
            checksum += result.weights[result.focus]
            precondition(result.children.count == count / 200)
            if reused { reuseCount += 1 }
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        precondition(checksum == count / 20 && reuseCount == (mode == "session" ? 10 : 0))
        let value: [String: Any] = ["mode": mode, "files": count, "nodes": snapshot.nodes.count,
            "initial_seconds": initialSeconds, "navigation_seconds": elapsed, "repeats": 10,
            "checksum": checksum, "reused_evaluations": reuseCount]
        print(String(decoding: try JSONSerialization.data(withJSONObject: value, options: .sortedKeys), as: UTF8.self))
    }
}
