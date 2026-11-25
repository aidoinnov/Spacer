import Foundation
import XCTest
import SpaceSnifferScanEngine
@testable import WindowsScanCore

final class WindowsOverviewTests: XCTestCase {
    private func node(_ id: Int, directory: Bool = true, logical: UInt64, allocated: UInt64) -> WindowsNode {
        WindowsNode(id: id, parent: id == 0 ? nil : 0, name: "n\(id)", path: "C:\\n\(id)",
            directory: directory, logical: logical, allocated: allocated, attributes: directory ? 16 : 0,
            boundary: false, children: [])
    }
    func testRootFilesCannotEvictEightKnownFoldersAndValuesStayCurrent() {
        var nodes = [node(0, logical: 0, allocated: 0)]
        var overview = WindowsOverview()
        for id in 1...32 {
            nodes.append(node(id, directory: false, logical: 100_000, allocated: 100_000))
            overview.observe(id, nodes: nodes, isNewRoot: true)
        }
        for id in 33...40 {
            nodes.append(node(id, logical: 1, allocated: 1))
            overview.observe(id, nodes: nodes, isNewRoot: true)
        }
        XCTAssertEqual(overview.rootFolderCount, 8)
        XCTAssertEqual(overview.roots(nodes).filter(\.directory).count, 8)
        nodes[33].logical = 500; nodes[33].allocated = 500
        XCTAssertEqual(overview.roots(nodes).first { $0.path == nodes[33].path }?.allocated, 500)
    }
    func testIndependentRankingsAreBoundedAndRetainSparseAndGrowingBranches() {
        var nodes = [node(0, logical: 0, allocated: 0)]
        var overview = WindowsOverview()
        for id in 1...1000 {
            nodes.append(node(id, logical: UInt64(1001-id), allocated: UInt64(id)))
            overview.observe(id, nodes: nodes, isNewRoot: true)
        }
        XCTAssertEqual(overview.roots(nodes).count, 32)
        nodes.append(node(1001, logical: 100_000, allocated: 0))
        overview.observe(1001, nodes: nodes)
        XCTAssertTrue(overview.roots(nodes).contains { $0.path == nodes[1001].path })
        nodes[500].logical = 200_000; nodes[500].allocated = 200_000
        overview.observe(500, nodes: nodes)
        XCTAssertTrue(overview.roots(nodes).contains { $0.path == nodes[500].path })
        XCTAssertLessThanOrEqual(overview.roots(nodes).count, 32)
    }
    private struct Reader: DirectoryBatchReader {
        func readDirectory(at path: String, control: ScanControl) -> Batch {
            if path == "C:\\overview" {
                return .listing((0..<8).map { NativeEntry(name: "d\($0)", directory: true, reparse: false,
                    attributes: 16, logical: 0, allocated: 0, identity: nil) })
            }
            return .listing([NativeEntry(name: "f", directory: false, reparse: false,
                attributes: 0, logical: 7, allocated: 4096, identity: nil)])
        }
    }
    private final class Capture: @unchecked Sendable {
        private let lock = NSLock()
        private var items: [WindowsProgress] = []
        func append(_ value: WindowsProgress) { lock.lock(); defer { lock.unlock() }; items.append(value) }
        var values: [WindowsProgress] { lock.lock(); defer { lock.unlock() }; return items }
    }
    func testBuilderPublishesEightCurrentBranchesAndFinalWireContract() throws {
        let capture = Capture()
        let snapshot = WindowsTreeBuilder.scan(root: "C:\\overview", control: ScanControl(),
            policy: WindowsScanPolicy(workers: 4), boundedReader: Reader(), inlineReader: Reader(),
            progress: { capture.append($0) })
        for event in capture.values {
            XCTAssertEqual(event.roots.filter(\.directory).reduce(0) { $0 + $1.logical }, event.logical)
            XCTAssertEqual(event.roots.filter(\.directory).reduce(0) { $0 + $1.allocated }, event.allocated)
        }
        let final = try XCTUnwrap(capture.values.last)
        XCTAssertEqual(final.roots.filter(\.directory).count, 8)
        XCTAssertEqual(final.logical, snapshot.nodes[0].logical)
        XCTAssertEqual(final.allocated, snapshot.nodes[0].allocated)
        let wire = try XCTUnwrap(JSONSerialization.jsonObject(with: JSONEncoder().encode(final)) as? [String: Any])
        XCTAssertEqual(wire["overviewVersion"] as? Int, 1)
        XCTAssertEqual(wire["rootFolderCount"] as? Int, 8)
    }

    func testNativeEightFoldersMatchEveryObservedTotal() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("overview-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for id in 0..<8 {
            let folder = root.appendingPathComponent("d\(id)")
            try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
            try Data(repeating: 1, count: 7).write(to: folder.appendingPathComponent("f"))
        }
        let capture = Capture()
        let snapshot = WindowsScanner.scan(root: root.path, control: ScanControl(), progress: { capture.append($0) })
        XCTAssertEqual(snapshot.files, 8)
        XCTAssertEqual(snapshot.nodes[0].logical, 56)
        for event in capture.values {
            XCTAssertEqual(event.roots.filter(\.directory).reduce(0) { $0 + $1.logical }, event.logical)
            XCTAssertEqual(event.roots.filter(\.directory).reduce(0) { $0 + $1.allocated }, event.allocated)
        }
        let final = try XCTUnwrap(capture.values.last)
        XCTAssertEqual(final.roots.filter(\.directory).count, 8)
        XCTAssertEqual(final.logical, 56)
        XCTAssertEqual(final.allocated, snapshot.nodes[0].allocated)
        XCTAssertEqual(final.rootFolderCount, 8)
    }

}
