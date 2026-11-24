import XCTest
import CoreGraphics
@testable import SpaceSnifferCore

/// Expectations below come from recorded Windows procedures and bytes, not from the Mac implementation.
final class ReferenceContractTests: XCTestCase {
    private func fixture() -> ScanSnapshot {
        var root = DiskNode(id: 0, parent: nil, path: "/root", name: "root", isDirectory: true,
                            logicalBytes: 3072, allocatedBytes: 8192, children: [1, 3])
        root.nativeAttributes = 0x10
        let folder = DiskNode(id: 1, parent: 0, path: "/root/temp", name: "temp", isDirectory: true,
                              logicalBytes: 1024, allocatedBytes: 4096, children: [2])
        var a = DiskNode(id: 2, parent: 1, path: "/root/temp/a.zip", name: "a.zip", logicalBytes: 1024,
                         allocatedBytes: 4096, modified: Date(timeIntervalSince1970: 100))
        a.nativeAttributes = 2; a.created = Date(timeIntervalSince1970: 80); a.accessed = Date(timeIntervalSince1970: 90)
        let b = DiskNode(id: 3, parent: 0, path: "/root/b.txt", name: "b.txt", logicalBytes: 2048,
                         allocatedBytes: 4096, modified: Date(timeIntervalSince1970: 150))
        return ScanSnapshot(rootPath: "/root", nodes: [root, folder, a, b])
    }
    func testNativeSemicolonMasksORAndExclusionsAND() throws {
        let s = fixture()
        // patternMatch_internal 0x445050 ORs positives and rejects ANY matching negative.
        XCTAssertTrue(try ScanFilter("*.zip;*.txt").matches(s.nodes[2], snapshot: s))
        XCTAssertTrue(try ScanFilter("*.zip;*.txt").matches(s.nodes[3], snapshot: s))
        XCTAssertFalse(try ScanFilter("*.zip,*.txt").matches(s.nodes[2], snapshot: s))
        XCTAssertFalse(try ScanFilter("*.zip;*.txt;|a.*").matches(s.nodes[2], snapshot: s))
        XCTAssertFalse(try ScanFilter("!*.txt").matches(s.nodes[3], snapshot: s))
    }
    func testNativeSizeBoundariesFuzzyPrefixAndFirstBound() throws {
        let s = fixture(); let n = s.nodes[2]
        // 0x444870 rejects <minimum and >maximum, so comparisons are inclusive.
        XCTAssertTrue(try ScanFilter("logicalsize>1kb;logicalsize<1kb").matches(n, snapshot: s))
        XCTAssertTrue(try ScanFilter("dsksz>4kb").matches(n, snapshot: s))
        XCTAssertTrue(try ScanFilter("logicalsize>1kb;logicalsize>2kb").matches(n, snapshot: s))
        XCTAssertThrowsError(try ScanFilter("logicalsize>1.5kb"))
    }
    func testNativeAgeUnitsFieldsAndFolderPrefix() throws {
        let s = fixture(); let n = s.nodes[2]; let now = Date(timeIntervalSince1970: 160)
        // isMinMaxAge 0x440810: m = 60 seconds; month = 2,592,000 seconds.
        XCTAssertTrue(try ScanFilter(">1m").matches(n, snapshot: s, now: now))
        XCTAssertFalse(try ScanFilter(">1month").matches(n, snapshot: s, now: now))
        XCTAssertTrue(try ScanFilter("creation>80s").matches(n, snapshot: s, now: now))
        XCTAssertTrue(try ScanFilter("a<70s").matches(n, snapshot: s, now: now))
        XCTAssertTrue(try ScanFilter("\\temp").matches(n, snapshot: s))
        XCTAssertFalse(try ScanFilter("|\\temp").matches(n, snapshot: s))
        XCTAssertFalse(try ScanFilter("temp/").matches(n, snapshot: s))
    }
    func testNativeTagsAreORWithExclusionAndGreenIsThree() throws {
        var s = fixture(); s.tags[s.nodes[1].path] = 4 // 0x740d93: "3", "green", "g"
        XCTAssertTrue(try ScanFilter(":3").matches(s.nodes[2], snapshot: s))
        XCTAssertTrue(try ScanFilter(":green;:red").matches(s.nodes[2], snapshot: s))
        XCTAssertFalse(try ScanFilter(":4").matches(s.nodes[2], snapshot: s))
        XCTAssertFalse(try ScanFilter(":tag:red+green-g").matches(s.nodes[2], snapshot: s))
        XCTAssertTrue(try ScanFilter(":attr:hidden").matches(s.nodes[2], snapshot: s))
        XCTAssertFalse(try ScanFilter("|:attr:hidden").matches(s.nodes[2], snapshot: s))
    }
    func testSelectionRevealsOneMoreLevelWithoutChangingRootOrSiblings() throws {
        let nodes = [
            DiskNode(id: 0, parent: nil, path: "/r", name: "r", isDirectory: true, logicalBytes: 100, children: [1, 4]),
            DiskNode(id: 1, parent: 0, path: "/r/a", name: "a", isDirectory: true, logicalBytes: 50, children: [2]),
            DiskNode(id: 2, parent: 1, path: "/r/a/b", name: "b", isDirectory: true, logicalBytes: 50, children: [3]),
            DiskNode(id: 3, parent: 2, path: "/r/a/b/file", name: "file", logicalBytes: 50),
            DiskNode(id: 4, parent: 0, path: "/r/c", name: "c", isDirectory: true, logicalBytes: 50, children: [5]),
            DiskNode(id: 5, parent: 4, path: "/r/c/other", name: "other", logicalBytes: 50)]
        let s = ScanSnapshot(rootPath: "/r", nodes: nodes); let weights = nodes.map(\.logicalBytes)
        let bounds = CGRect(x: 0, y: 0, width: 1000, height: 700)
        let initial = try XCTUnwrap(Treemap.tiles(snapshot: s, weights: weights, root: 0, depth: 1, in: bounds, control: ScanControl()))
        XCTAssertEqual(Set(initial.map(\.id)), [1, 4])
        let first = try XCTUnwrap(Treemap.tiles(snapshot: s, weights: weights, root: 0, depth: 1, selected: 1, in: bounds, control: ScanControl()))
        XCTAssertEqual(Set(first.map(\.id)), [1, 2, 4])
        let second = try XCTUnwrap(Treemap.tiles(snapshot: s, weights: weights, root: 0, depth: 1, selected: 2, in: bounds, control: ScanControl()))
        XCTAssertEqual(Set(second.map(\.id)), [1, 2, 3, 4])
        XCTAssertFalse(second.contains { $0.id == 5 })
        XCTAssertEqual(first.first { $0.id == 4 }?.rect, initial.first { $0.id == 4 }?.rect)
    }
    func testRenameKeepsTagButRemovalDoesNotTransferToExistingHardLink() {
        var old = DiskNode(id: 0, parent: nil, path: "/old", name: "old"); old.fileIdentity = "1:100"
        var renamed = old; renamed.path = "/new"; renamed.name = "new"
        XCTAssertEqual(TagPolicy.reconcile(["/old": 4], previous: [old], current: [renamed]), ["/new": 4])
        var alias = old; alias.path = "/alias"; alias.name = "alias"
        XCTAssertEqual(TagPolicy.reconcile(["/old": 4], previous: [old, alias], current: [alias]), [:])
    }
    func testNativeZoomCurveConstantsAndRectangleInterpolation() {
        // zoomFromTo 0x42bb40 and doubles [100, 3.1415, 1, 0.5] at 0x73f4e0.
        XCTAssertEqual(TreemapMotion.duration, 0.5)
        XCTAssertEqual(TreemapMotion.progress(0), 0)
        XCTAssertEqual(TreemapMotion.progress(1), 1)
        XCTAssertEqual(TreemapMotion.progress(0.5), 0.75, accuracy: 0.0001)
        var previous = 0.0
        for i in 0...100 {
            let current = TreemapMotion.progress(Double(i) / 100)
            XCTAssertGreaterThanOrEqual(current, previous); previous = current
        }
        let from = CGRect(x: 0, y: 0, width: 100, height: 50)
        let to = CGRect(x: 100, y: 50, width: 200, height: 100)
        XCTAssertEqual(TreemapMotion.interpolate(from: from, to: to, progress: 0), from)
        XCTAssertEqual(TreemapMotion.interpolate(from: from, to: to, progress: 1), to)
        XCTAssertEqual(TreemapMotion.interpolate(from: from, to: to, progress: 0.5), CGRect(x: 50, y: 25, width: 150, height: 75))
    }
    func testNativeSNSGoldenBytesAndMalformedRecords() throws {
        // Independently specified native v4 folder "/r" + one file "a", little-endian fields.
        let hex = "0403080000004c77427941413d3d010000000000000001000000000000001000000000000000000000000000000000000000000000000000000000000402040000005951413d0100000000000000010000000000000000000000000000000000000000000000000000000000000000000000000001000100"
        var golden = Data(); var i = hex.startIndex
        while i < hex.endIndex { let end = hex.index(i, offsetBy: 2); golden.append(UInt8(hex[i..<end], radix: 16)!); i = end }
        let s = try SNSSnapshot.decode(golden)
        XCTAssertEqual(s.rootPath, "/r"); XCTAssertEqual(s.nodes[1].name, "a")
        XCTAssertEqual(s.nodes[1].logicalBytes, 1); XCTAssertEqual(s.nodes.count, 2)
        XCTAssertThrowsError(try SNSSnapshot.decode(golden.dropLast()))
        XCTAssertThrowsError(try SNSSnapshot.decode(Data([4, 3, 1, 32, 0, 0]))) // length 8193
        let output = try SNSSnapshot.encode(s)
        let decoded = try SNSSnapshot.decode(output)
        XCTAssertEqual(decoded.nodes[1].path, "/r/a")
    }
    func testNativeSNSPreservesWindowsPathsWithoutMappingToMacFiles() throws {
        let root = DiskNode(id: 0, parent: nil, path: "C:\\Users", name: "Users", isDirectory: true, logicalBytes: 3, allocatedBytes: 4096, children: [1])
        let child = DiskNode(id: 1, parent: 0, path: "C:\\Users\\한글.txt", name: "한글.txt", logicalBytes: 3, allocatedBytes: 4096)
        let s = ScanSnapshot(rootPath: root.path, nodes: [root, child])
        let decoded = try SNSSnapshot.decode(SNSSnapshot.encode(s))
        XCTAssertEqual(decoded.nodes[1].path, child.path)
    }
}
