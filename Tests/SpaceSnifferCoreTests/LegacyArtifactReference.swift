import Foundation
@testable import SpaceSnifferCore

/// Frozen pre-streaming writers, independent format oracle (2026-11-09).
enum LegacyArtifactReference {
    typealias FormatError = SNSSnapshot.FormatError
    public static func encode(_ snapshot: ScanSnapshot, ids: Set<Int>? = nil, root: Int = 0) throws -> Data {
        guard snapshot.nodes.indices.contains(root) else { throw FormatError.malformed }
        var data = Data()
        func append<T: FixedWidthInteger>(_ value: T) { var little = value.littleEndian; withUnsafeBytes(of: &little) { data.append(contentsOf: $0) } }
        func date(_ value: Date?) -> UInt64 {
            guard let value else { return 0 }
            let ticks = (value.timeIntervalSince1970 + 11_644_473_600) * 10_000_000
            return ticks > 0 && ticks < Double(UInt64.max) ? UInt64(ticks) : 0
        }
        var stack: [(Int, Bool)] = [(root, false)]
        while let (id, end) = stack.popLast() {
            if end { data.append(contentsOf: [1, 0]); continue }
            guard id == root || ids == nil || ids!.contains(id) else { continue }
            let n = snapshot.nodes[id]
            let type: UInt8 = n.nativeType ?? (id == root && snapshot.isVolumeRoot ? 1 : n.isDirectory ? 3 : 2)
            let name = id == root ? n.path : n.name
            guard let utf16 = name.data(using: .utf16LittleEndian) else { throw FormatError.invalidName }
            let encoded = utf16.base64EncodedData()
            // Native writer truncates at 8192. Rejecting avoids silently changing a selected macOS filename.
            guard !encoded.isEmpty, encoded.count <= 8192 else { throw FormatError.invalidName }
            data.append(4); data.append(type); append(UInt32(encoded.count)); data.append(encoded)
            append(n.logicalBytes); append(n.allocatedBytes)
            append(n.nativeAttributes ?? (n.isDirectory ? UInt32(0x10) : 0))
            append(date(n.created)); append(date(n.accessed)); append(date(n.modified))
            data.append(UInt8(snapshot.tags[n.path] ?? 0)); data.append(n.nativeFlags ?? 0)
            stack.append((id, true))
            stack.append(contentsOf: n.children.reversed().map { ($0, false) })
        }
        return data
    }
    public static func simpleFileList(_ snapshot: ScanSnapshot, ids: Set<Int>, weights: [Int64], root: Int = 0) -> String {
        guard snapshot.nodes.indices.contains(root), weights.count == snapshot.nodes.count else { return "" }
        var lines: [String] = []; var stack = [root]
        while let id = stack.popLast() {
            let node = snapshot.nodes[id]
            guard id == root || ids.contains(id) else { continue }
            if !node.isDirectory && (node.nativeType == nil || node.nativeType == 2) { lines.append(node.path) }
            let children = node.children.filter { ids.contains($0) }.sorted {
                let a = snapshot.nodes[$0]; let b = snapshot.nodes[$1]
                if a.isDirectory != b.isDirectory { return !a.isDirectory }
                if weights[$0] != weights[$1] { return weights[$0] > weights[$1] }
                return $0 > $1
            }
            stack.append(contentsOf: children.reversed())
        }
        return lines.isEmpty ? "" : lines.joined(separator: "\r\n") + "\r\n"
    }
}
