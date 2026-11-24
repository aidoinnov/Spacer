import XCTest
@testable import SpaceSnifferCore

final class ScanProgressTests: XCTestCase {
    func testIntermediateSnapshotNodeVolumeIsLinearEvenWithMillionsOfProgressTicks() {
        var publication = ScanPublication()
        var copiedNodes = 0
        var publications = 0
        for count in 1...2_000_000 where publication.shouldPublish(nodeCount: count) {
            copiedNodes += count; publications += 1
        }
        XCTAssertLessThan(copiedNodes, 4_000_000)
        XCTAssertLessThan(publications, 25)
    }

    func testDeltaTotalsAndLightweightFinalProgressAgreeWithoutDoubleCounting() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sniffer-progress-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a/deep"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("b"), withIntermediateDirectories: true)
        for i in 0..<700 {
            let folder = i % 2 == 0 ? "a/deep" : "b"
            try Data(repeating: 42, count: i + 1).write(to: root.appendingPathComponent("\(folder)/\(i).bin"))
        }
        let capture = ProgressCapture()
        let result = DiskScanner.scan(root, metadataBackend: .automatic(.orderedScan), directoryConcurrency: 2, overviewDelay: 0,
                                      progress: { capture.snapshot($0) }, heartbeat: { capture.heartbeat($0) })
        XCTAssertEqual(result.nodes[0].logicalBytes, 245350)
        let ownAllocation = result.nodes.filter { !$0.isDirectory }.reduce(Int64(0)) { $0 + $1.allocatedBytes }
        XCTAssertEqual(result.nodes[0].allocatedBytes, ownAllocation)
        _ = try result.validated()
        let (snapshots, heartbeats) = capture.values()
        XCTAssertFalse(snapshots.isEmpty); XCTAssertFalse(heartbeats.isEmpty)
        XCTAssertTrue(snapshots.contains { $0.finished == nil && $0.fileCount > 0 && $0.fileCount < 700 })
        for snapshot in snapshots { _ = try snapshot.validated() }
        let last = try XCTUnwrap(heartbeats.last)
        XCTAssertEqual(last.fileCount, 700); XCTAssertEqual(last.folderCount, 4)
        XCTAssertEqual(last.logicalBytes, result.nodes[0].logicalBytes)
        XCTAssertEqual(last.allocatedBytes, result.nodes[0].allocatedBytes)
        XCTAssertEqual(last.pendingFolders, 0); XCTAssertEqual(last.visitedFolders, 4)
        XCTAssertEqual(heartbeats.map(\.sequence), heartbeats.map(\.sequence).sorted())
    }

    func testCancellationAfterFirstUsefulPublicationFlushesPendingByteDeltas() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sniffer-batch-cancel-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for i in 0..<700 { try Data(repeating: 1, count: i % 37).write(to: root.appendingPathComponent("f\(i)")) }
        let control = ScanControl(), capture = ProgressCapture()
        let result = DiskScanner.scan(root, control: control, metadataBackend: .automatic(.orderedScan), overviewDelay: 0,
                                      progress: { capture.snapshot($0) }, heartbeat: { value in
            capture.heartbeat(value)
            if value.fileCount > 0 { control.cancel() }
        })
        XCTAssertTrue(result.cancelled); XCTAssertGreaterThan(result.fileCount, 0); XCTAssertLessThan(result.fileCount, 700)
        _ = try result.validated()
        for snapshot in capture.values().0 { _ = try snapshot.validated() }
        XCTAssertEqual(result.nodes[0].logicalBytes, result.nodes.filter { !$0.isDirectory }.reduce(0) { $0 + $1.logicalBytes })
        XCTAssertEqual(capture.values().1.last?.logicalBytes, result.nodes[0].logicalBytes)
    }

    func testProgressCallbackCancelsLargeDirectoryWithConsistentPartialTotals() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sniffer-cancel-progress-" + UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for i in 0..<600 { try Data([1]).write(to: root.appendingPathComponent("\(i).bin")) }
        let control = ScanControl()
        let result = DiskScanner.scan(root, control: control, heartbeat: { _ in control.cancel() })
        XCTAssertTrue(result.cancelled)
        XCTAssertLessThan(result.fileCount, 600)
        XCTAssertEqual(result.nodes[0].logicalBytes, Int64(result.fileCount))
        _ = try result.validated()
    }
}

private final class ProgressCapture: @unchecked Sendable {
    private let lock = NSLock()
    private var snapshots: [ScanSnapshot] = []
    private var heartbeats: [ScanProgress] = []
    func snapshot(_ value: ScanSnapshot) { lock.lock(); defer { lock.unlock() }; snapshots.append(value) }
    func heartbeat(_ value: ScanProgress) { lock.lock(); defer { lock.unlock() }; heartbeats.append(value) }
    func values() -> ([ScanSnapshot], [ScanProgress]) { lock.lock(); defer { lock.unlock() }; return (snapshots, heartbeats) }
}
