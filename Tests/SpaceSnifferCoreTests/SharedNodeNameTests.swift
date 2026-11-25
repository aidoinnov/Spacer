import XCTest
#if canImport(SpaceSnifferCore)
@testable import SpaceSnifferCore
#else
@testable import ExplorerDomain
#endif

final class SharedNodeNameTests: XCTestCase {
    func testSharedNodeStorageBudget() {
        XCTAssertEqual(MemoryLayout<DiskNode>.stride, 184)
        print("NODE_STORAGE_STRIDE \(MemoryLayout<DiskNode>.stride)")
    }

    func testParentPresencePreservesEveryIntAndIndependentCopies() throws {
        var value = DiskNode(id: 0, parent: nil, path: "/", name: "/")
        let absent = value
        let parents: [Int?] = [0, -1, Int.min, Int.max, nil, 0, nil]
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        for parent in parents {
            let frozen = value
            let prior = value.parent
            value.parent = parent
            XCTAssertEqual(value.parent, parent)
            XCTAssertEqual(frozen.parent, prior)
            let restored = try JSONDecoder().decode(DiskNode.self, from: encoder.encode(value))
            XCTAssertEqual(restored, value)
            XCTAssertEqual(restored.parent, parent)
            if parent == nil { XCTAssertEqual(value, absent) }
        }
    }

    func testNameMutationPreservesPathSpellingAndFrozenSnapshot() throws {
        let leaf = "cafe\u{301}😀"
        let path = "/한글/" + leaf
        let node = DiskNode(id: 1, parent: 0,
                            storedPath: NodePathStorage(base: "/한글", leaf: leaf), name: leaf)
        var nodes = NodeTable([node])
        let frozen = nodes
        nodes[0].name = "café😀" // Equal as Swift String, different UTF-8 spelling.
        XCTAssertEqual(Array(nodes[0].path.utf8), Array(path.utf8))
        XCTAssertEqual(Array(frozen[0].name.utf8), Array(leaf.utf8))
        XCTAssertEqual(Array(frozen[0].path.utf8), Array(path.utf8))
        let expected = DiskNode(id: 1, parent: 0, path: path, name: "café😀")
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(nodes[0]), try encoder.encode(expected))
        nodes[0].path = "\\\\server\\share\\file"
        nodes[0].name = "renamed"
        XCTAssertEqual(nodes[0].path, "\\\\server\\share\\file")
        XCTAssertEqual(try JSONDecoder().decode(DiskNode.self, from: encoder.encode(nodes[0])), nodes[0])
    }

    func testMismatchedLeafAndNameNeverBecomeCoupled() throws {
        for (leaf, name) in [("cafe\u{301}", "café"), ("actual", "display"), ("", "name")] {
            var value = DiskNode(id: 1, parent: 0,
                                 storedPath: NodePathStorage(base: "/base/", leaf: leaf), name: name)
            let originalPath = value.path
            value.name = "changed"
            XCTAssertEqual(Array(value.path.utf8), Array(originalPath.utf8))
            let literal = DiskNode(id: 1, parent: 0, path: originalPath, name: "changed")
            XCTAssertEqual(value, literal)
        }
    }

    func testPathMutationDoesNotChangeNameOrNativeMetadata() throws {
        var value = DiskNode(id: 1, parent: 0,
                            storedPath: NodePathStorage(base: "/", leaf: "file"), name: "file")
        value.setNativeFileIdentity(device: Int64.min, inode: UInt64.max)
        value.nativeFlags = 0; value.nativeType = UInt8.max
        value.created = .distantPast; value.ownAllocatedBytes = Int64.max
        let frozen = value
        value.path = "C:\\arbitrary\\different-name"
        XCTAssertEqual(value.name, frozen.name)
        XCTAssertEqual(value.fileIdentity, frozen.fileIdentity)
        XCTAssertEqual(value.nativeFlags, frozen.nativeFlags)
        XCTAssertEqual(value.nativeType, frozen.nativeType)
        XCTAssertEqual(value.created, frozen.created)
        XCTAssertEqual(value.ownAllocatedBytes, frozen.ownAllocatedBytes)
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        XCTAssertEqual(try encoder.encode(try JSONDecoder().decode(DiskNode.self, from: encoder.encode(value))), try encoder.encode(value))
    }
}
