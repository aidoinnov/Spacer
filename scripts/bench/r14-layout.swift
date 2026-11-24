import Foundation
import SpaceSnifferCore

let values: [String: Int] = ["disk_node_stride": MemoryLayout<DiskNode>.stride,
    "disk_node_size": MemoryLayout<DiskNode>.size, "disk_node_alignment": MemoryLayout<DiskNode>.alignment,
    "node_table_stride": MemoryLayout<NodeTable>.stride, "string_stride": MemoryLayout<String>.stride,
    "array_int_stride": MemoryLayout<[Int]>.stride, "int_stride": MemoryLayout<Int>.stride]
print(String(decoding: try JSONSerialization.data(withJSONObject: values, options: [.sortedKeys]), as: UTF8.self))
