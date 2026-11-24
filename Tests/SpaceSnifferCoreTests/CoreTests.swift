import XCTest
import Foundation
import CoreGraphics
import Darwin
@testable import SpaceSnifferCore

final class CoreTests: XCTestCase {
    private func fixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sniffer-tests-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url.appendingPathComponent("nested"), withIntermediateDirectories: true)
        try Data(repeating: 7, count: 16384).write(to: url.appendingPathComponent("large.zip"))
        try Data(repeating: 3, count: 2048).write(to: url.appendingPathComponent("nested/note.txt"))
        try Data().write(to: url.appendingPathComponent("empty"))
        try Data(repeating: 4, count: 1024).write(to: url.appendingPathComponent(".hidden"))
        return url
    }
    func testScannerTotalsSymlinkLoopAndHardLinks() throws {
        let url = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        try FileManager.default.createSymbolicLink(at: url.appendingPathComponent("nested/loop"), withDestinationURL: url)
        try FileManager.default.linkItem(at: url.appendingPathComponent("large.zip"), to: url.appendingPathComponent("copy.zip"))
        let snapshot = DiskScanner.scan(url)
        XCTAssertEqual(snapshot.folderCount, 2)
        XCTAssertEqual(snapshot.fileCount, 5)
        XCTAssertEqual(snapshot.issueCount, 0)
        let links = snapshot.nodes.filter { $0.name == "copy.zip" || $0.name == "large.zip" }
        XCTAssertEqual(links.filter { $0.allocatedBytes > 0 }.count, 2)
        XCTAssertFalse(snapshot.nodes.contains { $0.isSymbolicLink })
        XCTAssertEqual(snapshot.nodes[0].logicalBytes, 16384 * 2 + 2048 + 1024)
        XCTAssertEqual(try snapshot.validated().nodes.count, snapshot.nodes.count)
        let weights = try ScanFilter("").weights(in: snapshot, mode: .allocated)
        XCTAssertEqual(weights[0], snapshot.nodes[0].allocatedBytes)
    }
    func testCancelledAndMissingRoot() throws {
        let url = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let control = ScanControl(); control.cancel()
        let cancelled = DiskScanner.scan(url, control: control)
        XCTAssertTrue(cancelled.cancelled); XCTAssertNotNil(cancelled.finished)
        XCTAssertEqual(cancelled.nodes.count, 1)
        let missing = DiskScanner.scan(url.appendingPathComponent("does-not-exist"))
        XCTAssertTrue(missing.nodes.isEmpty); XCTAssertEqual(missing.issueCount, 1)
    }
    func testFiltersAndAncestorTags() throws {
        let url = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        var snapshot = DiskScanner.scan(url)
        let zip = try XCTUnwrap(snapshot.nodes.first { $0.name == "large.zip" })
        let note = try XCTUnwrap(snapshot.nodes.first { $0.name == "note.txt" })
        let folder = try XCTUnwrap(snapshot.nodes.first { $0.name == "nested" })
        snapshot.tags[folder.path] = 1
        XCTAssertTrue(try ScanFilter("*.zip;logicalsize>10kb").matches(zip, snapshot: snapshot))
        XCTAssertFalse(try ScanFilter("*.zip;logicalsize>10kb").matches(note, snapshot: snapshot))
        XCTAssertTrue(try ScanFilter("*.zip;*.txt").matches(note, snapshot: snapshot))
        XCTAssertTrue(try ScanFilter(":tag:red;\\nested").matches(note, snapshot: snapshot))
        XCTAssertFalse(try ScanFilter("|:tag:red").matches(note, snapshot: snapshot))
        XCTAssertTrue(try ScanFilter(":class:Archives/Disk images").matches(zip, snapshot: snapshot))
        XCTAssertTrue(try ScanFilter("<1d").matches(zip, snapshot: snapshot))
        XCTAssertFalse(try ScanFilter(">30d").matches(zip, snapshot: snapshot))
        XCTAssertThrowsError(try ScanFilter(">nonsense"))
        XCTAssertFalse(try ScanFilter(":invalid").matches(zip, snapshot: snapshot))
        XCTAssertThrowsError(try ScanFilter(">999999999999999999999999tb"))
        let filtered = try ScanFilter("*.zip").weights(in: snapshot, mode: .logical)
        XCTAssertEqual(filtered[0], 16384)
        let hidden = try ScanFilter("").weights(in: snapshot, mode: .logical, showHidden: false)
        XCTAssertEqual(snapshot.nodes[0].logicalBytes - hidden[0], 1024)
    }
    func testSnapshotRoundtripAndCorruptGraphRejection() throws {
        let url = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let snapshot = DiskScanner.scan(url)
        let decoded = try JSONDecoder().decode(ScanSnapshot.self, from: JSONEncoder().encode(snapshot)).validated()
        XCTAssertEqual(decoded.nodes[0].logicalBytes, snapshot.nodes[0].logicalBytes)
        var corrupt = snapshot; corrupt.nodes[0].children.append(0)
        XCTAssertThrowsError(try corrupt.validated())
        corrupt = snapshot; corrupt.nodes[1].path = "/tmp/elsewhere"
        XCTAssertThrowsError(try corrupt.validated())
        corrupt = snapshot; corrupt.tags["bad"] = 100
        XCTAssertThrowsError(try corrupt.validated())
    }
    func testReportIncludesEmptyMatchesAndRespectsHiddenPaths() throws {
        let url = try fixture(); defer { try? FileManager.default.removeItem(at: url) }
        let snapshot = DiskScanner.scan(url)
        let all = try ScanFilter("").matchingIDs(in: snapshot, showHidden: false)
        XCTAssertTrue(all.contains { snapshot.nodes[$0].name == "empty" })
        XCTAssertFalse(all.contains { snapshot.nodes[$0].name == ".hidden" })
        let empty = try ScanFilter("empty").matchingIDs(in: snapshot)
        XCTAssertTrue(empty.contains { snapshot.nodes[$0].name == "empty" })
    }
    func testNativeFileListWritesOnlyPaths() {
        let root = DiskNode(id: 0, parent: nil, path: "/r", name: "r", isDirectory: true, logicalBytes: 3, children: [1, 2])
        let a = DiskNode(id: 1, parent: 0, path: "/r/a", name: "a", logicalBytes: 1)
        let b = DiskNode(id: 2, parent: 0, path: "/r/b", name: "b", logicalBytes: 2)
        let s = ScanSnapshot(rootPath: "/r", nodes: [root, a, b])
        XCTAssertEqual(Report.simpleFileList(s, ids: [0, 1, 2], weights: [3, 1, 2]), "/r/b\n/r/a\n")
    }
    func testSquarifiedLayoutConservesAreaAndNeverOverlaps() {
        let bounds = CGRect(x: 11, y: 19, width: 1024, height: 640)
        let items = (0..<180).map { ($0, Double(($0 * 37) % 983 + 1)) }
        let result = Treemap.layout(items, in: bounds)
        XCTAssertEqual(result.count, items.count)
        let sum = items.reduce(0) { $0 + $1.1 }
        var area = 0.0
        for tile in result {
            XCTAssertGreaterThanOrEqual(tile.rect.minX, bounds.minX - 0.00001)
            XCTAssertGreaterThanOrEqual(tile.rect.minY, bounds.minY - 0.00001)
            XCTAssertLessThanOrEqual(tile.rect.maxX, bounds.maxX + 0.00001)
            XCTAssertLessThanOrEqual(tile.rect.maxY, bounds.maxY + 0.00001)
            let tileArea = tile.rect.width * tile.rect.height
            XCTAssertEqual(tileArea, items[tile.id].1 / sum * bounds.width * bounds.height, accuracy: 0.001)
            area += tileArea
        }
        XCTAssertEqual(area, bounds.width * bounds.height, accuracy: 0.01)
        for i in result.indices {
            for j in result.indices where j > i {
                let intersection = result[i].rect.intersection(result[j].rect)
                XCTAssertTrue(intersection.isNull || intersection.width * intersection.height < 0.00001)
            }
        }
        XCTAssertTrue(Treemap.layout([(0, 0), (1, -3), (2, .nan)], in: bounds).isEmpty)
    }
}
