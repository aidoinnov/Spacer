import Foundation
import Darwin

/// Same-module optimized candidate profile; not an app benchmark.
@main enum NativeScanProfile {
    static func main() throws {
        let a = CommandLine.arguments; precondition(a.count == 4)
        let mode = a[1], root = URL(fileURLWithPath: a[2]), iterations = Int(a[3])!
        var checksum: UInt64 = 14695981039346656037
        func feed(_ value: String) { for b in value.utf8 { checksum = (checksum ^ UInt64(b)) &* 1099511628211 } }
        var seconds = 0.0; var nodeCount = 0, files = 0, folders = 0, issues = 0
        for _ in 0..<iterations {
            let start = clock_gettime_nsec_np(CLOCK_UPTIME_RAW)
            let snapshot = DiskScanner.scan(root, metadataBackend: mode == "bulk" ? .bulk(NativeDirectoryMetadata()) : .posix)
            seconds += Double(clock_gettime_nsec_np(CLOCK_UPTIME_RAW) - start) / 1e9
            precondition(!snapshot.cancelled)
            nodeCount = snapshot.nodes.count; files = snapshot.fileCount; folders = snapshot.folderCount; issues = snapshot.issueCount
            // Independent equality suite checks all fields. This checksum excludes
            // naturally changing access timestamps and process volume samples.
            for node in snapshot.nodes {
                feed("\(node.id)|\(node.parent ?? -1)|\(node.path)|\(node.name)|\(node.isDirectory)|\(node.fileIdentity ?? "")|\(node.logicalBytes)|\(node.allocatedBytes)|\(node.ownAllocatedBytes)|\(node.nativeAttributes)|\(node.children)\n")
            }
        }
        var usage = rusage(); getrusage(RUSAGE_SELF, &usage)
        let result: [String: Any] = ["mode":mode,"root":root.path,"iterations":iterations,"seconds":seconds,"checksum":String(checksum),"nodes":nodeCount,"files":files,"folders":folders,"issues":issues,"max_rss_bytes":usage.ru_maxrss,"scope":"optimized actual Scanner; scan-only timed, checksum outside timer; owned fixture, concurrent GUI scan/other agents; no whole-volume claim"]
        print(String(decoding: try JSONSerialization.data(withJSONObject: result,options:[.sortedKeys]),as:UTF8.self))
    }
}
