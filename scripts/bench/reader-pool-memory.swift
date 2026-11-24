import Foundation
import Darwin

private struct DigestSink: ArtifactByteSink {
    var value = UInt64(14695981039346656037)
    mutating func append(_ bytes: UnsafeRawBufferPointer) throws {
        for byte in bytes { value = (value ^ UInt64(byte)) &* 1099511628211 }
    }
}

@main enum ReaderPoolMemoryProbe {
    static func main() throws {
        let mode = CommandLine.arguments[1]
        let data = try Data(contentsOf: URL(fileURLWithPath: CommandLine.arguments[2]), options: .mappedIfSafe)
        let start = DispatchTime.now().uptimeNanoseconds
        let roots = try mode == "legacy" ? LegacyReader.decodeAll(data) : SNSSnapshot.decodeAll(data)
        let seconds = Double(DispatchTime.now().uptimeNanoseconds - start) / 1e9
        var usage = rusage(); let usageCode = getrusage(RUSAGE_SELF, &usage)
        var vm = task_vm_info_data_t()
        var count = mach_msg_type_number_t(MemoryLayout<task_vm_info_data_t>.size / MemoryLayout<natural_t>.size)
        let vmCode = withUnsafeMutablePointer(to: &vm) { pointer in
            pointer.withMemoryRebound(to: integer_t.self, capacity: Int(count)) {
                task_info(mach_task_self_, task_flavor_t(TASK_VM_INFO), $0, &count)
            }
        }
        // Compare every decoded field using deterministic canonical SNS bytes,
        // outside the decoder timer and in its own temporary-object pool.
        var hashes: [String] = []
        for snapshot in roots {
            var sink = DigestSink()
            try SNSSnapshot.write(snapshot, to: &sink)
            hashes.append(String(sink.value, radix: 16))
        }
        print(String(decoding: try JSONSerialization.data(withJSONObject: ["mode": mode, "seconds": seconds,
            "decoder_max_rss_bytes": usageCode == 0 ? Int64(usage.ru_maxrss) : -1,
            "decoder_physical_footprint_bytes": vmCode == KERN_SUCCESS ? Int64(vm.phys_footprint) : -1,
            "roots": roots.count, "nodes": roots.map { $0.nodes.count }, "canonical_checksums": hashes], options: .sortedKeys), as: UTF8.self))
    }
}
