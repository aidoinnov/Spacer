import Foundation

// Compile with the core sources; keeps the previous published tree alive like a UI subscriber.
final class ScanMeasurements: @unchecked Sendable {
    private let lock = NSLock()
    private var previous: ScanSnapshot?
    private var publications = 0
    private var copiedNodes = 0
    private var heartbeats = 0
    func publish(_ value: ScanSnapshot) {
        lock.lock(); defer { lock.unlock() }
        previous = value; publications += 1; copiedNodes += value.nodes.count
    }
    func pulse(_ value: ScanProgress) { lock.lock(); defer { lock.unlock() }; heartbeats += 1 }
    func metrics() -> [String: Int] {
        lock.lock(); defer { lock.unlock() }
        return ["treePublications": publications, "publishedNodeVolume": copiedNodes, "heartbeats": heartbeats]
    }
}

guard CommandLine.arguments.count == 2 else { fatalError("Usage: scan-benchmark /absolute/folder") }
let metrics = ScanMeasurements()
let start = Date()
let result = DiskScanner.scan(URL(fileURLWithPath: CommandLine.arguments[1]), progress: { metrics.publish($0) }, heartbeat: { metrics.pulse($0) })
var output: [String: Any] = metrics.metrics()
output["seconds"] = Date().timeIntervalSince(start)
output["nodes"] = result.nodes.count
output["files"] = result.fileCount
output["folders"] = result.folderCount
output["logicalBytes"] = result.nodes.first?.logicalBytes ?? 0
output["allocatedBytes"] = result.nodes.first?.allocatedBytes ?? 0
output["issues"] = result.issueCount
output["cancelled"] = result.cancelled
_ = try result.validated()
print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: [.sortedKeys]), as: UTF8.self))
