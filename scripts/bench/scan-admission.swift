import Foundation

@main enum ScanAdmissionBenchmark {
    static func main() async throws {
        let mode = CommandLine.arguments[1]
        let root = URL(fileURLWithPath: CommandLine.arguments[2])
        let rootCount = Int(CommandLine.arguments.dropFirst(3).first ?? "8")!
        let admission = mode == "detached" ? nil : ScanAdmission(limit: Int(mode)!)
        defer { admission?.shutdown() }
        let start = ProcessInfo.processInfo.systemUptime
        let results = try await withThrowingTaskGroup(of: ScanSnapshot.self) { group in
            for i in 0..<rootCount {
                let path = root.appendingPathComponent("root-\(i)")
                group.addTask {
                    if let admission {
                        return try await withCheckedThrowingContinuation { continuation in
                            do {
                                try admission.submit(control: ScanControl(), operation: { DiskScanner.scan(path) }, completion: { result in
                                    switch result {
                                    case .finished(let snapshot): continuation.resume(returning: snapshot)
                                    case .cancelledBeforeStart: continuation.resume(throwing: CancellationError())
                                    }
                                })
                            } catch { continuation.resume(throwing: error) }
                        }
                    }
                    // Match ScanService's old detached callback path. Awaiting a
                    // Task.value here would escalate utility priority and skew comparison.
                    return await withCheckedContinuation { continuation in
                        Task.detached(priority: .utility) { continuation.resume(returning: DiskScanner.scan(path)) }
                    }
                }
            }
            var values: [ScanSnapshot] = []
            for try await value in group { values.append(value) }
            return values
        }
        let elapsed = ProcessInfo.processInfo.systemUptime - start
        precondition(results.count == rootCount && results.allSatisfy { $0.fileCount == 1000 && $0.nodes[0].logicalBytes == 256000 && $0.issueCount == 0 })
        let stats = admission?.statistics()
        let record: [String: Any] = ["mode": mode, "roots": rootCount, "seconds": elapsed, "files": results.reduce(0) { $0 + $1.fileCount },
            "checksum": results.reduce(Int64(0)) { $0 + $1.nodes[0].logicalBytes }, "peak_admitted": stats?.peakActive ?? -1]
        print(String(decoding: try JSONSerialization.data(withJSONObject: record, options: .sortedKeys), as: UTF8.self))
    }
}
