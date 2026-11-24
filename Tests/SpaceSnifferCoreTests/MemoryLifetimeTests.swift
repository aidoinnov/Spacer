import XCTest
@testable import SpaceSnifferCore

final class MemoryLifetimeTests: XCTestCase, @unchecked Sendable {
    func testThousandPendingLatestJobsReleaseSupersededAndCancelledCaptures() async {
        let worker = LatestWorker<Int>(name: "test.latest.burst")
        let gate = DispatchSemaphore(value: 0); defer { gate.signal(); worker.shutdown() }
        let entered = expectation(description: "running job held")
        let done = expectation(description: "running job returns")
        worker.submit(operation: { _ in entered.fulfill(); _ = gate.wait(timeout: .now()+5); done.fulfill(); return 1 }, completion: { _ in XCTFail("cancelled completion") })
        await fulfillment(of: [entered], timeout: 2)
        let released = expectation(description: "all pending captures released before running job exits"); released.expectedFulfillmentCount = 1000
        for _ in 0..<1000 {
            let capture = LifetimeCapture { released.fulfill() }
            worker.submit(operation: { [capture] _ in XCTFail("obsolete pending operation ran"); return capture.value }, completion: { _ in XCTFail("obsolete pending completion") })
        }
        worker.cancel()
        await fulfillment(of: [released], timeout: 2)
        let stats = WorkerTelemetry.shared.snapshot()["test.latest.burst"]!
        XCTAssertEqual(stats.submitted, 1001); XCTAssertEqual(stats.coalesced, 999)
        XCTAssertEqual(stats.started, 1); XCTAssertEqual(stats.active, 1)
        gate.signal(); await fulfillment(of: [done], timeout: 2)
    }
    func testIdleWorkerReleasesCompletedOperationCaptures() async {
        let worker = LatestWorker<Int>(); defer { worker.shutdown() }
        let released = expectation(description: "completed capture released while worker is idle")
        let completed = expectation(description: "job completed")
        func enqueue() {
            let capture = LifetimeCapture { released.fulfill() }
            worker.submit(operation: { [capture] _ in capture.value }, completion: { _ in completed.fulfill() })
        }
        enqueue()
        await fulfillment(of: [completed, released], timeout: 3)
    }

    func testSnapshotCopiesRemainIndependentAcrossPageBoundariesAndAppend() {
        var table = NodeTable()
        for id in 0..<4097 { table.append(DiskNode(id: id, parent: nil, path: "/\(id)", name: "\(id)", logicalBytes: Int64(id))) }
        let frozen = table
        table[0].logicalBytes = -1
        table[1023].name = "changed"
        table[1024].children.append(7)
        table[4096].allocatedBytes = 100
        table.append(DiskNode(id: 4097, parent: nil, path: "/new", name: "new"))
        XCTAssertEqual(frozen.count, 4097); XCTAssertEqual(table.count, 4098)
        XCTAssertEqual(frozen[0].logicalBytes, 0); XCTAssertEqual(frozen[1023].name, "1023")
        XCTAssertTrue(frozen[1024].children.isEmpty); XCTAssertEqual(frozen[4096].allocatedBytes, 0)
        XCTAssertEqual(table[1024].children, [7])
        table.removeAll(); XCTAssertEqual(frozen.count, 4097)
    }

    func testNodeTableCodableRemainsAFlatArray() throws {
        let table = NodeTable([DiskNode(id: 0, parent: nil, path: "/root", name: "root")])
        let data = try JSONEncoder().encode(table)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [[String: Any]])
        XCTAssertEqual(json.count, 1)
        let restored = try JSONDecoder().decode(NodeTable.self, from: data)
        XCTAssertEqual(restored[0].path, "/root")
    }

    func testConcurrentFrozenReaderAndPagedWriterAreIsolated() async {
        var table = NodeTable()
        for id in 0..<5000 { table.append(DiskNode(id: id, parent: nil, path: "/\(id)", name: "\(id)", logicalBytes: 1)) }
        let frozen = table
        let reader = Task.detached { frozen.reduce(Int64(0)) { $0 + $1.logicalBytes } }
        for id in table.indices { table[id].logicalBytes = 2 }
        let sum = await reader.value
        XCTAssertEqual(sum, 5000)
        XCTAssertEqual(table.reduce(Int64(0)) { $0 + $1.logicalBytes }, 10000)
    }

    func testSubtreeMergeAddsNewBranchWithoutLosingExistingSibling() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sniffer-memory-merge-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([1]).write(to: root.appendingPathComponent("keep.bin"))
        let original = DiskScanner.scan(root)
        let branch = root.appendingPathComponent("new")
        try FileManager.default.createDirectory(at: branch, withIntermediateDirectories: true)
        try Data([2, 3]).write(to: branch.appendingPathComponent("added.bin"))
        let merged = try XCTUnwrap(SnapshotTree.replacing(original, with: DiskScanner.scan(branch), control: ScanControl()))
        XCTAssertEqual(merged.fileCount, 2); XCTAssertEqual(merged.nodes[0].logicalBytes, 3)
        XCTAssertTrue(merged.nodes.contains { $0.name == "keep.bin" })
        _ = try merged.validated()
        XCTAssertEqual(original.fileCount, 1); XCTAssertEqual(original.nodes[0].logicalBytes, 1)
    }
}

private final class LifetimeCapture: @unchecked Sendable {
    let value = 1
    let release: @Sendable () -> Void
    init(_ release: @escaping @Sendable () -> Void) { self.release = release }
    deinit { release() }
}
