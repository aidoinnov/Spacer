import XCTest
@testable import SpaceSnifferCore

final class ScanOverviewTests: XCTestCase {
    func testLargeOrderingIndexUsesRawBytesAndRejectsDuplicateOrMissingNames() throws {
        let names = ["cafe\u{301}", "café"] + (0..<5000).map { "f\($0)" }
        let entries = names.reversed().map { NativeDirectoryMetadata.Entry(name: $0, values: nil, directoryEntryCount: nil) }
        var ordered = entries
        XCTAssertTrue(OrderedDirectoryReader.orderEntries(&ordered, names: names))
        XCTAssertEqual(ordered.map { Array($0.name.utf8) }, names.map { Array($0.utf8) })
        var duplicate = entries; duplicate[0] = duplicate[1]
        let invalidBefore = duplicate.map { Array($0.name.utf8) }
        XCTAssertFalse(OrderedDirectoryReader.orderEntries(&duplicate, names: names))
        XCTAssertEqual(duplicate.map { Array($0.name.utf8) }, invalidBefore)
        var shortened = Array(entries.dropLast())
        XCTAssertFalse(OrderedDirectoryReader.orderEntries(&shortened, names: names))
        var missing = names; missing[0] = "absent"
        var absent = entries
        XCTAssertFalse(OrderedDirectoryReader.orderEntries(&absent, names: missing))
        XCTAssertEqual(absent.map { Array($0.name.utf8) }, entries.map { Array($0.name.utf8) })
        // The successful inout reorder also leaves an aliased reader unchanged.
        XCTAssertEqual(entries.map { Array($0.name.utf8) }, names.reversed().map { Array($0.utf8) })
    }

    func testEntryPermutationMovesMetadataThroughEverySmallCycle() {
        let names = (0..<6).map { "n\($0)" }
        func verify(_ order: [Int], _ remaining: [Int]) {
            if !remaining.isEmpty {
                for value in remaining { verify(order + [value], remaining.filter { $0 != value }) }
                return
            }
            var entries = order.map { NativeDirectoryMetadata.Entry(name: names[$0], values: nil, directoryEntryCount: UInt32($0)) }
            XCTAssertTrue(OrderedDirectoryReader.orderEntries(&entries, names: names))
            XCTAssertEqual(entries.map(\.name), names)
            XCTAssertEqual(entries.map(\.directoryEntryCount), (0..<6).map { UInt32($0) })
        }
        verify([], Array(0..<6))
        var empty: [NativeDirectoryMetadata.Entry] = []
        XCTAssertTrue(OrderedDirectoryReader.orderEntries(&empty, names: []))
    }
    func testAncestorUpdateKeepsPreviouslyPublishedPagesUnchanged() {
        var nodes = NodeTable()
        for id in 0..<1500 {
            nodes.append(DiskNode(id: id, parent: id == 0 ? nil : id-1, path: "/\(id)", name: "\(id)",
                isDirectory: true, isSymbolicLink: false, logicalBytes: 0, allocatedBytes: 0, modified: Date()))
        }
        let published = nodes
        nodes.addObservedBytes(logical: 7, allocated: 4096, startingAt: 1499)
        XCTAssertTrue(nodes.allSatisfy { $0.logicalBytes == 7 && $0.allocatedBytes == 4096 })
        XCTAssertTrue(published.allSatisfy { $0.logicalBytes == 0 && $0.allocatedBytes == 0 })
        nodes.addObservedBytes(logical: 3, allocated: 4096, startingAt: 500)
        XCTAssertEqual(nodes[500].logicalBytes, 10)
        XCTAssertEqual(nodes[501].logicalBytes, 7)
    }
    func testBoundedTopFoldersRetainsGrowingCandidatesAndCanonicalTies() {
        var accumulator = ScanOverviewAccumulator()
        for id in (0..<500).reversed() {
            var node = DiskNode(id: id, parent: 0, path: "/\(id)", name: "\(id)", isDirectory: true,
                isSymbolicLink: false, logicalBytes: 100, allocatedBytes: 100, modified: Date())
            accumulator.observeFolder(node)
            if id == 499 { node.allocatedBytes = 1000; accumulator.observeFolder(node) }
        }
        XCTAssertEqual(accumulator.value.folders.count, 16)
        XCTAssertEqual(accumulator.value.folders.first?.id, 499)
        XCTAssertEqual(accumulator.value.folders.dropFirst().map(\.id), Array(0..<15))
        var growing = DiskNode(id: 400, parent: 0, path: "/400", name: "400", isDirectory: true,
            isSymbolicLink: false, logicalBytes: 2000, allocatedBytes: 2000, modified: Date())
        accumulator.observeFolder(growing)
        growing.logicalBytes = 3000; accumulator.observeFolder(growing)
        XCTAssertEqual(accumulator.value.folders.first?.logicalBytes, 3000)
        XCTAssertEqual(accumulator.value.folders.first?.id, 400)
    }

    func testSharedScanOverviewIsBoundedArrivesBeforeCompletionAndMatchesFinalTree() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("overview-"+UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for branch in 0..<24 {
            let folder = root.appendingPathComponent("d\(branch)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            for file in 0..<80 { try Data(repeating: 1, count: 1+branch*1000+file).write(to: folder.appendingPathComponent("f\(file)")) }
        }
        let capture = OverviewCapture()
        let result = DiskScanner.scan(root, metadataBackend: .automatic(.orderedScan), directoryConcurrency: 4, overviewDelay: 0,
            heartbeat: { capture.accept($0) })
        let updates = capture.values
        XCTAssertTrue(updates.contains { $0.fileCount > 0 && $0.fileCount < result.fileCount && $0.overview?.largeFiles.isEmpty == false })
        XCTAssertTrue(updates.allSatisfy { ($0.overview?.folders.count ?? 0) <= 16 && ($0.overview?.largeFiles.count ?? 0) <= 16 })
        XCTAssertEqual(updates.map(\.fileCount), updates.map(\.fileCount).sorted())
        let overview = try XCTUnwrap(updates.last?.overview)
        XCTAssertEqual(overview.observedNodeCount, result.nodes.count)
        func ranked(_ nodes: [DiskNode]) -> [Int] {
            Array(nodes.filter { $0.allocatedBytes > 0 }.sorted {
                $0.allocatedBytes == $1.allocatedBytes ? $0.id < $1.id : $0.allocatedBytes > $1.allocatedBytes
            }.prefix(16).map(\.id))
        }
        XCTAssertEqual(overview.folders.map(\.id), ranked(result.nodes.filter { $0.parent == 0 && $0.isDirectory }))
        XCTAssertEqual(overview.largeFiles.map(\.id), ranked(result.nodes.filter { !$0.isDirectory }))
        for item in overview.folders + overview.largeFiles {
            XCTAssertEqual(item.allocatedBytes, result.nodes[item.id].allocatedBytes)
            XCTAssertEqual(item.logicalBytes, result.nodes[item.id].logicalBytes)
        }
        let encoded = try JSONEncoder().encode(overview)
        XCTAssertEqual(try JSONDecoder().decode(ScanOverview.self, from: encoded), overview)
        let deferred = OverviewCapture()
        let fast = DiskScanner.scan(root, metadataBackend: .automatic(.orderedScan), overviewDelay: 3600,
            heartbeat: { deferred.accept($0) })
        XCTAssertEqual(fast.fileCount, result.fileCount)
        XCTAssertTrue(deferred.values.allSatisfy { $0.overview == nil })
    }
}

private final class OverviewCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var updates: [ScanProgress] = []
    func accept(_ value: ScanProgress) { lock.lock(); updates.append(value); lock.unlock() }
    var values: [ScanProgress] { lock.lock(); defer { lock.unlock() }; return updates }
}
