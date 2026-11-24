import Foundation
import Darwin
import CryptoKit

/// Same-module release scanner benchmark. Callback-ready data is not GUI draw latency.
private final class Capture: @unchecked Sendable {
    let start = DispatchTime.now().uptimeNanoseconds
    private let lock = NSLock()
    private var previous: ScanSnapshot?
    private var samples: [[String: Any]] = []
    private var firstOverviewMilliseconds: Double?
    func acceptOverview(_ value: ScanProgress) {
        lock.lock(); defer { lock.unlock() }
        if firstOverviewMilliseconds == nil, value.overview?.largeFiles.isEmpty == false {
            firstOverviewMilliseconds = Double(DispatchTime.now().uptimeNanoseconds - start)/1e6
        }
    }
    var firstOverview: Double? { lock.withLock { firstOverviewMilliseconds } }
    func accept(_ snapshot: ScanSnapshot) {
        lock.lock(); defer { lock.unlock() }
        previous = snapshot // retain immutable publication as an actual reader does
        guard let root = snapshot.nodes.first else { return }
        var groups: [String: Int64] = [:]
        for id in root.children where snapshot.nodes[id].isDirectory {
            groups[snapshot.nodes[id].name] = snapshot.nodes[id].allocatedBytes
        }
        samples.append(["elapsed_ms": Double(DispatchTime.now().uptimeNanoseconds - start)/1e6,
                        "observed_bytes":root.allocatedBytes, "groups":groups,
                        "files":snapshot.fileCount, "nodes":snapshot.nodes.count])
    }
    func values() -> [[String: Any]] { lock.withLock { samples } }
}

@main enum ProgressiveProfile {
    static func main() throws {
        guard CommandLine.arguments.count == 3 else {
            fputs("usage: profile posix|bulk|stream|ordered|automatic|all PATH\n", stderr); exit(64)
        }
        let mode = CommandLine.arguments[1], path = CommandLine.arguments[2]
        let backend: DiskScanner.MetadataBackend
        switch mode {
        case "posix": backend = .posix
        case "bulk": backend = .bulk(.init())
        case "stream": backend = .streaming(.init())
        case "ordered": backend = DiskScanner.orderedMetadataBackend
        case "automatic": backend = DiskScanner.defaultMetadataBackend
        case "all": backend = DiskScanner.defaultMetadataBackend
        case "parallel2", "parallel4": backend = DiskScanner.defaultMetadataBackend
        default: exit(64)
        }
        func diskIO() -> rusage_info_v2? {
            var value = rusage_info_v2()
            let status = withUnsafeMutablePointer(to: &value) { pointer in
                proc_pid_rusage(getpid(), Int32(RUSAGE_INFO_V2),
                    UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: rusage_info_t?.self))
            }
            return status == 0 ? value : nil
        }
        var before = rusage(); getrusage(RUSAGE_SELF, &before)
        let beforeDisk = diskIO()
        var io = ScanIOStatistics()
        let capture = Capture()
        let result = DiskScanner.scan(URL(fileURLWithPath: path), metadataBackend: backend,
                                      volumeTraversal: mode == "all" ? .allVolumes : .selectedVolume,
                                      directoryConcurrency: mode == "parallel2" ? 2 : mode == "parallel4" ? 4 : 1,
                                      progress: { capture.accept($0) }, heartbeat: { capture.acceptOverview($0) }, diagnostics: { io = $0 })
        let completed = DispatchTime.now().uptimeNanoseconds
        var after = rusage(); getrusage(RUSAGE_SELF, &after)
        let afterDisk = diskIO()
        capture.accept(result)
        _ = try result.validated()
        // Independent Python POSIX manifest uses this canonical schema. Node IDs
        // and enumeration order intentionally are not part of filesystem identity.
        var hash = SHA256()
        let prefix = result.rootPath.hasSuffix("/") ? result.rootPath : result.rootPath + "/"
        for node in result.nodes.sorted(by: { $0.path < $1.path }) {
            let relative = node.id == 0 ? "." : String(node.path.dropFirst(prefix.count))
            let logical = node.isDirectory ? 0 : node.logicalBytes
            let allocated = node.isDirectory ? 0 : node.allocatedBytes
            let row = "\(relative)\t\(node.isDirectory ? 1 : 0)\t\(node.fileIdentity ?? "")\t\(logical)\t\(allocated)\t\(node.nativeAttributes ?? 0)\t\(Int64(node.modified.timeIntervalSince1970))\n"
            hash.update(data: Data(row.utf8))
        }
        func cpu(_ r: rusage) -> Double {
            Double(r.ru_utime.tv_sec + r.ru_stime.tv_sec) + Double(r.ru_utime.tv_usec + r.ru_stime.tv_usec)/1e6
        }
        var output: [String: Any] = ["mode":mode,"root":result.rootPath,
            "scan_complete_ms":Double(completed-capture.start)/1e6,
            "peak_rss_mib":Double(after.ru_maxrss)/1048576,
            "cpu_seconds":cpu(after)-cpu(before),"files":result.fileCount,"folders":result.folderCount,
            "allocated_bytes":result.nodes.first?.allocatedBytes ?? 0,
            "logical_bytes":result.nodes.first?.logicalBytes ?? 0,
            "issue_count":result.issueCount,"cancelled":result.cancelled,
            "digest":hash.finalize().map { String(format:"%02x",$0) }.joined(),
            "publications":capture.values(),
            "scope":"release engine, reader retained, callback-ready only; not GUI latency; RSS/CPU sampled before checksum" ]
        output["enumeration_io"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(io))
        output["peak_directory_sections"] = DirectoryIOBudget.shared.observation.peak
        output["first_observed_overview_ms"] = capture.firstOverview.map { $0 as Any } ?? NSNull()
        if let coverage = result.volumeCoverage { output["volume_coverage"] = try JSONSerialization.jsonObject(with: JSONEncoder().encode(coverage)) }
        output["metadata_requests_per_entry"] = Double(io.statCalls + io.bulkCalls) / Double(max(1, result.nodes.count))
        if let beforeDisk, let afterDisk {
            output["read_bytes"] = afterDisk.ri_diskio_bytesread >= beforeDisk.ri_diskio_bytesread ? afterDisk.ri_diskio_bytesread - beforeDisk.ri_diskio_bytesread : 0
            output["write_bytes"] = afterDisk.ri_diskio_byteswritten >= beforeDisk.ri_diskio_byteswritten ? afterDisk.ri_diskio_byteswritten - beforeDisk.ri_diskio_byteswritten : 0
        } else {
            output["read_bytes"] = NSNull(); output["write_bytes"] = NSNull()
        }
        output["io_scope"] = "scanner stat/bulk API counts; process physical I/O via proc_pid_rusage V2 (cached reads may be zero); readdir calls are not kernel syscall counts"
        print(String(decoding:try JSONSerialization.data(withJSONObject:output, options:[.sortedKeys]),as:UTF8.self))
    }
}
