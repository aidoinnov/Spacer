import Foundation

/// Native Simple file list: paths only, files first, size descending, reverse-child-position ties, UTF8/LF.
/// REA ctor 0x413b30, compareTo 0x46b6b0, buildExportRow 0x416e60,
/// actExportExecute 0x41c270 opens "wb+" (0x73dfef), so LF is not CRT-translated.
public enum Report {
    public static func simpleFileList(_ snapshot: ScanSnapshot, ids: Set<Int>, weights: [Int64], root: Int = 0) -> String {
        var lines: [String] = []
        visit(snapshot, weights: weights, root: root, includes: ids.contains) { lines.append($0) }
        return lines.isEmpty ? "" : lines.joined(separator: "\n") + "\n"
    }
    public static func write<S: ArtifactByteSink>(_ snapshot: ScanSnapshot, ids: Set<Int>, weights: [Int64], root: Int = 0, to sink: inout S) throws {
        try visit(snapshot, weights: weights, root: root, includes: ids.contains) { path in
            try sink.utf8(path); try sink.integer(UInt8(0x0a))
        }
    }
    static func write<S: ArtifactByteSink>(_ snapshot: ScanSnapshot, selected: [Bool], weights: [Int64], root: Int, to sink: inout S) throws {
        guard selected.count == snapshot.nodes.count else { return }
        try visit(snapshot, weights: weights, root: root, includes: { selected[$0] }) { path in
            try sink.utf8(path); try sink.integer(UInt8(0x0a))
        }
    }
    private static func visit(_ snapshot: ScanSnapshot, weights: [Int64], root: Int, includes: (Int) -> Bool, emit: (String) throws -> Void) rethrows {
        guard snapshot.nodes.indices.contains(root), weights.count == snapshot.nodes.count else { return }
        var stack = [root]
        while let id = stack.popLast() {
            let node = snapshot.nodes[id]
            guard id == root || includes(id) else { continue }
            if !node.isDirectory && (node.nativeType == nil || node.nativeType == 2) { try emit(node.path) }
            let positions = NativeReportOrdering.positions(snapshot, root: id, weights: weights, spec: .simple, includes: includes)
            for position in positions.reversed() { stack.append(node.children[position]) }
        }
    }
}
