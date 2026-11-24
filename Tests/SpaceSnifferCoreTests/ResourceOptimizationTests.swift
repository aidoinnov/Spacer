import XCTest
@testable import SpaceSnifferCore

final class ResourceOptimizationTests: XCTestCase {
    func testFastMasksAgreeWithAnchoredUnicodeFallbackForASCIIUnicodeAndControlCharacters() throws {
        let masks = ["*.bin", "*.TXT", "*", "literal", "*.", "pre*.bin", "a?b", "?.bin", "한글*", "[x].bin"]
        var names = ["a.bin", "A.BIN", ".bin", "literal", "LITERAL", "한글.bin", "İ.bin", "K.bin", "é.bin", "[x].bin", "a.bin\n", "a\n.bin", ""]
        for value in 0..<32 { names.append("a" + String(UnicodeScalar(value)!) + ".bin") }
        for id in 0..<200 { names.append("file-\(id)." + (id % 2 == 0 ? "BIN" : "txt")) }
        var snapshot = ScanSnapshot(rootPath: "/m")
        snapshot.nodes.append(DiskNode(id: 0, parent: nil, path: "/m", name: "m", isDirectory: true))
        for (index, name) in names.enumerated() {
            snapshot.nodes.append(DiskNode(id: index + 1, parent: 0, path: "/m/" + name, name: name))
        }
        for mask in masks {
            let filter = try ScanFilter(mask)
            // A complete-name Unicode fallback. Original ASCII byte-glob
            // equivalence is checked separately against 0x445370's recursion.
            let expression = "\\A" + NSRegularExpression.escapedPattern(for: mask.lowercased())
                .replacingOccurrences(of: "\\*", with: "[\\s\\S]*").replacingOccurrences(of: "\\?", with: "[\\s\\S]") + "\\z"
            let oracle = try NSRegularExpression(pattern: expression, options: .caseInsensitive)
            for node in snapshot.nodes.dropFirst() {
                let expected = oracle.firstMatch(in: node.name, range: NSRange(node.name.startIndex..., in: node.name)) != nil
                XCTAssertEqual(filter.matches(node, snapshot: snapshot), expected, "\(mask) / \(node.name.debugDescription)")
            }
        }
    }

    private func fixture() -> ScanSnapshot {
        var s = ScanSnapshot(rootPath: "/r", nodes: [
            DiskNode(id: 0, parent: nil, path: "/r", name: "r", isDirectory: true, logicalBytes: 13, allocatedBytes: 12288, children: [1, 4]),
            DiskNode(id: 1, parent: 0, path: "/r/a", name: "a", isDirectory: true, logicalBytes: 3, allocatedBytes: 8192, children: [2, 3]),
            DiskNode(id: 2, parent: 1, path: "/r/a/one.bin", name: "one.bin", logicalBytes: 1, allocatedBytes: 4096),
            DiskNode(id: 3, parent: 1, path: "/r/a/two.txt", name: "two.txt", logicalBytes: 2, allocatedBytes: 4096),
            DiskNode(id: 4, parent: 0, path: "/r/other.bin", name: "other.bin", logicalBytes: 10, allocatedBytes: 4096)])
        s.fileCount = 3; s.folderCount = 2
        s.nodes[0].nativeType = 1 // drive labels are not folder-pattern ancestors
        s.nodes[1].nativeAttributes = 2
        s.tags = ["/r": 1, "/r/a": 4, "/r/a/two.txt": 2]
        return s
    }

    func testPackedAncestorContextAgreesWithIndependentPerFileEvaluation() throws {
        let s = fixture()
        for text in ["", ";", "*.bin", "\\a;*.bin", "|\\a;*.bin", "\\r;*.bin", ":red;*.bin", ":green", ":red;|:green", ":yellow", ":attr:hidden", "logicalsize>2b"] {
            let filter = try ScanFilter(text)
            for showHidden in [true, false] {
                var expected = Array(repeating: Int64(0), count: s.nodes.count)
                for node in s.nodes where !node.isDirectory {
                    var cursor: Int? = node.id; var hidden = false
                    while let id = cursor { hidden = hidden || (s.nodes[id].nativeAttributes ?? 0) & 2 != 0; cursor = s.nodes[id].parent }
                    if (showHidden || !hidden) && filter.matches(node, snapshot: s) { expected[node.id] = node.logicalBytes }
                }
                for id in stride(from: s.nodes.count - 1, through: 1, by: -1) {
                    if let parent = s.nodes[id].parent { expected[parent] += expected[id] }
                }
                XCTAssertEqual(filter.weights(in: s, mode: .logical, showHidden: showHidden), expected, text)
            }
        }
    }

    func testSameTopologyPatchPreservesIDsAndUnrelatedValuesWithPositiveAndNegativeDelta() throws {
        let original = fixture()
        var subtree = ScanSnapshot(rootPath: "/r/a", nodes: [
            DiskNode(id: 0, parent: nil, path: "/r/a", name: "a", isDirectory: true, logicalBytes: 4, allocatedBytes: 8192, children: [1, 2]),
            DiskNode(id: 1, parent: 0, path: "/r/a/one.bin", name: "one.bin", logicalBytes: 2, allocatedBytes: 4096),
            DiskNode(id: 2, parent: 0, path: "/r/a/two.txt", name: "two.txt", logicalBytes: 2, allocatedBytes: 4096)])
        let changed = try XCTUnwrap(SnapshotTree.replacing(original, with: subtree, control: ScanControl()))
        XCTAssertEqual(changed.started, subtree.started)
        XCTAssertEqual(changed.nodes.map(\.path), original.nodes.map(\.path))
        XCTAssertEqual(changed.nodes[0].logicalBytes, 14); XCTAssertEqual(changed.nodes[4], original.nodes[4])
        XCTAssertEqual(original.nodes[0].logicalBytes, 13)
        _ = try changed.validated()
        subtree.nodes[0].logicalBytes = 2; subtree.nodes[0].allocatedBytes = 4096
        subtree.nodes[1].logicalBytes = 0; subtree.nodes[1].allocatedBytes = 0
        let shrunk = try XCTUnwrap(SnapshotTree.replacing(changed, with: subtree, control: ScanControl()))
        XCTAssertEqual(shrunk.nodes[0].logicalBytes, 12); XCTAssertEqual(shrunk.nodes[0].allocatedBytes, 8192)
        XCTAssertEqual(shrunk.nodes[4], original.nodes[4]); _ = try shrunk.validated()
    }

    func testTopologyChangeFallsBackToCorrectReindexing() throws {
        let original = fixture()
        let subtree = ScanSnapshot(rootPath: "/r/a", nodes: [
            DiskNode(id: 0, parent: nil, path: "/r/a", name: "a", isDirectory: true, logicalBytes: 5, allocatedBytes: 4096, children: [1]),
            DiskNode(id: 1, parent: 0, path: "/r/a/new.bin", name: "new.bin", logicalBytes: 5, allocatedBytes: 4096)])
        let changed = try XCTUnwrap(SnapshotTree.replacing(original, with: subtree, control: ScanControl()))
        XCTAssertEqual(changed.fileCount, 2); XCTAssertEqual(changed.nodes[0].logicalBytes, 15)
        XCTAssertFalse(changed.nodes.contains { $0.name == "one.bin" }); XCTAssertTrue(changed.nodes.contains { $0.name == "new.bin" })
        _ = try changed.validated()
    }

    func testHierarchicalLookupHonoursExactPathAndWindowsRootBoundaries() {
        let s = fixture()
        XCTAssertEqual(SnapshotTree.nodeID(at: "/r/a/one.bin", in: s), 2)
        XCTAssertNil(SnapshotTree.nodeID(at: "/r/ab/one.bin", in: s))
        XCTAssertNil(SnapshotTree.nodeID(at: "/r/a//one.bin", in: s))
        let windows = ScanSnapshot(rootPath: "C:\\", nodes: [
            DiskNode(id: 0, parent: nil, path: "C:\\", name: "C:", isDirectory: true, children: [1]),
            DiskNode(id: 1, parent: 0, path: "C:\\한글", name: "한글", isDirectory: true, children: [2]),
            DiskNode(id: 2, parent: 1, path: "C:\\한글\\file.bin", name: "file.bin")])
        XCTAssertEqual(SnapshotTree.nodeID(at: "C:\\한글\\file.bin", in: windows), 2)
        XCTAssertNil(SnapshotTree.nodeID(at: "C:\\한글x\\file.bin", in: windows))
    }
}
