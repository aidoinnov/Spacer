import Foundation
import Darwin
import CryptoKit

/// In-memory storage probe: no filesystem scan or fixture I/O. Both versions
/// build the same metadata/path spellings and sample before validation/hash.
@main enum ModelMemoryProbe {
    static func usage() -> rusage_info_v2 {
        var value = rusage_info_v2()
        let status = withUnsafeMutablePointer(to: &value) { pointer in
            proc_pid_rusage(getpid(), Int32(RUSAGE_INFO_V2), UnsafeMutableRawPointer(pointer).assumingMemoryBound(to: rusage_info_t?.self))
        }
        precondition(status == 0)
        return value
    }
    static func node(id: Int, parent: Int?, path: String, name: String, directory: Bool) -> DiskNode {
        var result = DiskNode(id: id, parent: parent, path: path, name: name, isDirectory: directory,
                              logicalBytes: directory ? 0 : 1, allocatedBytes: directory ? 0 : 4096,
                              modified: Date(timeIntervalSince1970: 1_700_000_000))
        result.created = result.modified; result.accessed = result.modified
        result.nativeAttributes = directory ? 0x10 : 0; result.nativeFlags = 0; result.nativeType = directory ? 3 : 2
        result.ownAllocatedBytes = directory ? 0 : 4096
        #if NATIVE_IDENTITY
        result.setNativeFileIdentity(device: 16_777_234, inode: 8_000_000_000 + UInt64(id))
        #else
        result.fileIdentity = "16777234:" + String(8_000_000_000 + UInt64(id))
        #endif
        return result
    }
    static func main() throws {
        guard CommandLine.arguments.count == 2, let count = Int(CommandLine.arguments[1]), count > 0 else { exit(64) }
        let branches = min(1000, count)
        let root = "/fixture/" + String(repeating: "p", count: 48)
        let before = usage()
        let started = DispatchTime.now().uptimeNanoseconds
        var snapshot = ScanSnapshot(rootPath: root)
        snapshot.nodes.append(node(id: 0, parent: nil, path: root, name: String(repeating: "p", count: 48), directory: true))
        var parents: [String] = []
        for index in 0..<branches {
            let name = "b" + String(index), path = root + "/" + name, id = snapshot.nodes.count
            parents.append(path)
            snapshot.nodes.append(node(id: id, parent: 0, path: path, name: name, directory: true))
            snapshot.nodes[0].children.append(id)
        }
        for index in 0..<count {
            let parent = 1 + index % branches, name = "f" + String(index), id = snapshot.nodes.count
            // Same expression in both probes: isolate identity storage from
            // the separate production SnapshotPath.join optimization.
            let path = parents[parent-1] + "/" + name
            snapshot.nodes.append(node(id: id, parent: parent, path: path, name: name, directory: false))
            snapshot.nodes[parent].children.append(id)
            snapshot.nodes[parent].logicalBytes += 1; snapshot.nodes[parent].allocatedBytes += 4096
        }
        snapshot.fileCount = count; snapshot.folderCount = branches + 1
        snapshot.nodes[0].logicalBytes = Int64(count); snapshot.nodes[0].allocatedBytes = Int64(count) * 4096
        let elapsed = DispatchTime.now().uptimeNanoseconds - started
        let after = usage()
        var peak = rusage(); getrusage(RUSAGE_SELF, &peak)
        _ = try snapshot.validated()
        var hash = SHA256()
        for value in snapshot.nodes {
            let row = "\(value.id)\t\(value.parent ?? -1)\t\(value.path)\t\(value.name)\t\(value.logicalBytes)\t\(value.allocatedBytes)\t\(value.fileIdentity ?? "")\n"
            hash.update(data: Data(row.utf8))
        }
        let digest = hash.finalize().map { String(format: "%02x", $0) }.joined()
        let output: [String: Any] = ["files":count, "folders":branches+1, "nodes":snapshot.nodes.count,
            "logical_bytes":snapshot.nodes[0].logicalBytes, "allocated_bytes":snapshot.nodes[0].allocatedBytes,
            "digest":digest, "node_stride_bytes":MemoryLayout<DiskNode>.stride,
            "rss_before_bytes":before.ri_resident_size, "rss_after_build_bytes":after.ri_resident_size,
            "footprint_after_build_bytes":after.ri_phys_footprint, "peak_rss_before_validation_bytes":peak.ru_maxrss,
            "build_ms":Double(elapsed)/1e6,
            "scope":"synthetic in-memory model, identical long paths and metadata; not filesystem/GUI scan speed; sampled before validation and digest"]
        print(String(decoding: try JSONSerialization.data(withJSONObject: output, options: .sortedKeys), as: UTF8.self))
    }
}
