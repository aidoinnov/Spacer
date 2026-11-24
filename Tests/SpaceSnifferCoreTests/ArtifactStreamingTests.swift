import XCTest
import Darwin
@testable import SpaceSnifferCore

final class ArtifactStreamingTests: XCTestCase, @unchecked Sendable {
    private func directory() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sniffer-artifact-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true); return root
    }
    private func fixture(windows: Bool = false) -> ScanSnapshot {
        let root = windows ? "C:\\데이터" : "/데이터"
        let a = SnapshotPath.join(root, "a")
        var s = ScanSnapshot(rootPath: root, nodes: [
            DiskNode(id: 0, parent: nil, path: root, name: "데이터", isDirectory: true, logicalBytes: 100, allocatedBytes: 16384, children: [1, 4]),
            DiskNode(id: 1, parent: 0, path: a, name: "a", isDirectory: true, logicalBytes: 7, allocatedBytes: 8192, children: [2, 3]),
            DiskNode(id: 2, parent: 1, path: SnapshotPath.join(a, "zero.bin"), name: "zero.bin"),
            DiskNode(id: 3, parent: 1, path: SnapshotPath.join(a, "한글🙂.bin"), name: "한글🙂.bin", logicalBytes: 7, allocatedBytes: 8192),
            DiskNode(id: 4, parent: 0, path: SnapshotPath.join(root, "tie.txt"), name: "tie.txt", logicalBytes: 7, allocatedBytes: 4096)])
        s.tags = [root: 15, a: 1]; s.nodes[1].nativeAttributes = 2
        s.nodes[0].nativeType = 1; s.isVolumeRoot = true
        s.nodes[2].nativeFlags = 0x10; s.nodes[3].nativeFlags = 0x7f; s.nodes[3].nativeAttributes = 0x820
        for id in s.nodes.indices { s.nodes[id].modified = Date(timeIntervalSince1970: 1_700_000_000); s.nodes[id].created = .distantPast; s.nodes[id].accessed = Date(timeIntervalSince1970: 0) }
        return s
    }
    /// Independent fixed-fixture order; old CRLF writer remains frozen in
    /// LegacyArtifactReference. Never normalize line endings inside paths.
    private func nativeLFText(_ snapshot: ScanSnapshot, ids: Set<Int>, root: Int) -> String {
        let order: [Int]
        switch root {
        case 0: order = (ids.contains(4) ? [4] : []) + (ids.contains(1) ? [3,2].filter(ids.contains) : [])
        case 1: order = [3,2].filter(ids.contains)
        case 2: order = [2]
        default: order = []
        }
        return order.map { snapshot.nodes[$0].path + "\n" }.joined()
    }
    func testStreamingCodecsMatchFrozenWritersAcrossFiltersScopesUnicodeAndHiddenState() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        for windows in [false, true] {
            let s = fixture(windows: windows)
            for text in ["", "*.bin", "nomatch", ":red", "\\a", "logicalsize>0b"] {
                let filter = try ScanFilter(text)
                for hidden in [false, true] {
                    let ids = Set(filter.matchingIDs(in: s, showHidden: hidden))
                    let weights = filter.weights(in: s, mode: .logical, showHidden: hidden)
                    for root in [0, 1, 2] {
                        let sns = try LegacyArtifactReference.encode(s, ids: ids, root: root)
                        XCTAssertEqual(try SNSSnapshot.encode(s, ids: ids, root: root), sns)
                        var sink = ArtifactDataSink(); try SNSSnapshot.write(s, ids: ids, root: root, to: &sink)
                        XCTAssertEqual(sink.value, sns)
                        let txt = nativeLFText(s, ids: ids, root: root)
                        XCTAssertEqual(Report.simpleFileList(s, ids: ids, weights: weights, root: root), txt)
                        let snsURL = dir.appendingPathComponent("out.sns"); let txtURL = dir.appendingPathComponent("out.txt")
                        try ArtifactTransfer.save(s, filter: filter, showHidden: hidden, root: root, to: snsURL, now: now)
                        try ArtifactTransfer.export(s, filter: filter, mode: .logical, showHidden: hidden, root: root, to: txtURL, now: now)
                        XCTAssertEqual(try Data(contentsOf: snsURL), sns)
                        XCTAssertEqual(try Data(contentsOf: txtURL), Data(txt.utf8))
                    }
                }
            }
        }
    }
    func testOneTimestampAndZeroByteMembershipAreKeptBeforeAncestorPropagation() throws {
        let s = fixture(); let now = Date(timeIntervalSince1970: 1_700_000_060)
        let filter = try ScanFilter("*.bin;modified<60s")
        let selection = ArtifactSelection.report(s, filter: filter, mode: .logical, showHidden: true, now: now)
        XCTAssertTrue(selection.selected[0]); XCTAssertTrue(selection.selected[1]); XCTAssertTrue(selection.selected[2])
        XCTAssertEqual(selection.weights, [7, 7, 0, 7, 0])
        let expired = ArtifactSelection.report(s, filter: filter, mode: .logical, showHidden: true, now: now.addingTimeInterval(1))
        XCTAssertFalse(expired.selected.contains(true)); XCTAssertEqual(expired.weights, [0, 0, 0, 0, 0])
    }
    func testByteSinkBoundariesAndSourceBoundProjectionRemainStable() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let output = dir.appendingPathComponent("chunks")
        let transaction = try ArtifactFileTransaction(to: output, replaceExisting: false)
        var sink = ArtifactFileSink(transaction, limit: 7); var expected = Data()
        for size in [0, 1, 6, 7, 8, 21, 2, 5] {
            let bytes = Data((0..<size).map { UInt8($0) }); expected.append(bytes)
            try bytes.withUnsafeBytes { try sink.append($0) }
        }
        try sink.finish(); XCTAssertEqual(try Data(contentsOf: output), expected)
        var source = fixture()
        let projection = ArtifactProjection(source, filter: try ScanFilter("*.bin"), mode: .logical, showHidden: true, root: 1)
        source.nodes[3].logicalBytes = 1000; source.tags = [:]
        XCTAssertEqual(projection.matchedBytes, 7)
        let sns = dir.appendingPathComponent("projected.sns")
        try ArtifactTransfer.save(projection, to: sns)
        XCTAssertEqual(try SNSSnapshot.decode(Data(contentsOf: sns)).nodes[0].logicalBytes, 7)
    }
    func testShortWritesAndInterruptsProduceCompleteIdenticalFile() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let s = fixture(); let output = dir.appendingPathComponent("output.sns")
        let io = FaultArtifactIO(maxWrite: 3, interruptFirst: true)
        try ArtifactTransfer.save(s, ids: nil, root: 0, to: output, replaceExisting: false, io: io)
        XCTAssertEqual(try Data(contentsOf: output), try LegacyArtifactReference.encode(s))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["output.sns"])
    }
    func testWriteAndCloseAndPublishErrorsPreserveExistingOutputAndCleanStaging() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let output = dir.appendingPathComponent("old.sns"); let original = Data("existing".utf8)
        for io in [FaultArtifactIO(failWrite: true), FaultArtifactIO(maxWrite: 3, failAfter: 20), FaultArtifactIO(failClose: true), FaultArtifactIO(failPublish: true), FaultArtifactIO(zeroWrite: true)] {
            try original.write(to: output)
            XCTAssertThrowsError(try ArtifactTransfer.save(fixture(), ids: nil, root: 0, to: output, replaceExisting: true, io: io))
            XCTAssertEqual(try Data(contentsOf: output), original)
            XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["old.sns"])
        }
    }
    func testExclusivePublicationRaceCannotOverwriteAnotherWritersOutput() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let output = dir.appendingPathComponent("race.txt")
        let transaction = try ArtifactFileTransaction(to: output, replaceExisting: false)
        try Data("staged".utf8).withUnsafeBytes { try transaction.writeAll($0) }
        try Data("winner".utf8).write(to: output, options: .withoutOverwriting)
        XCTAssertThrowsError(try transaction.commit()); transaction.abort()
        XCTAssertEqual(try String(contentsOf: output, encoding: .utf8), "winner")
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["race.txt"])
    }
    func testAbortLeavesReplacedTemporaryInodeAndAtomicReplacePreservesPermissionsAndSymlinkTarget() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let target = dir.appendingPathComponent("target"); try Data("old".utf8).write(to: target); chmod(target.path, 0o640)
        let link = dir.appendingPathComponent("link"); try FileManager.default.createSymbolicLink(atPath: link.path, withDestinationPath: target.path)
        let transaction = try ArtifactFileTransaction(to: link, replaceExisting: true)
        try Data("new".utf8).withUnsafeBytes { try transaction.writeAll($0) }; try transaction.commit()
        XCTAssertEqual(try String(contentsOf: target, encoding: .utf8), "old")
        XCTAssertEqual(try String(contentsOf: link, encoding: .utf8), "new")
        XCTAssertEqual((try FileManager.default.attributesOfItem(atPath: link.path)[.posixPermissions] as? NSNumber)?.intValue, 0o640)
        let aborted = try ArtifactFileTransaction(to: dir.appendingPathComponent("not-created"), replaceExisting: false)
        try FileManager.default.moveItem(atPath: aborted.temporaryPath, toPath: dir.appendingPathComponent("moved").path)
        try Data("foreign".utf8).write(to: URL(fileURLWithPath: aborted.temporaryPath))
        XCTAssertThrowsError(try aborted.commit()); aborted.abort()
        XCTAssertEqual(try String(contentsOfFile: aborted.temporaryPath, encoding: .utf8), "foreign")
    }
    func testMalformedSNSAndReadErrorsDoNotPublishPartialOutput() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let output = dir.appendingPathComponent("invalid.sns")
        var s = fixture(); s.nodes[3].name = String(repeating: "長", count: 5000)
        XCTAssertThrowsError(try ArtifactTransfer.save(s, to: output))
        XCTAssertFalse(FileManager.default.fileExists(atPath: output.path))
        XCTAssertTrue(try FileManager.default.contentsOfDirectory(atPath: dir.path).isEmpty)
        let bad = dir.appendingPathComponent("bad.sns"); try Data([4, 3, 0]).write(to: bad)
        do { _ = try await ArtifactWorker.shared.load(bad); XCTFail() } catch {}
        do { _ = try await ArtifactWorker.shared.load(dir.appendingPathComponent("missing")); XCTFail() } catch {}
    }
    func testQueuedExportKeepsCapturedSnapshotFilterAndScope() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let executor = ArtifactIOExecutor(); let worker = ArtifactWorker(executor: executor)
        let gate = DispatchSemaphore(value: 0); defer { gate.signal() }
        let started = expectation(description: "block previous I/O")
        let blocker = Task { try await executor.run { started.fulfill(); gate.wait() } }
        await fulfillment(of: [started], timeout: 3)
        var current = fixture(); let captured = current; let filter = try ScanFilter("*.bin")
        let output = dir.appendingPathComponent("captured.txt")
        let export = Task { try await worker.export(captured, filter: filter, mode: .logical, showHidden: true, root: 1, to: output) }
        for _ in 0..<3000 {
            if executor.outstandingCount == 2 { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(executor.outstandingCount, 2)
        current.nodes[3].name = "changed.txt"; current.nodes[3].path = "/new/changed.txt"; current.nodes[3].logicalBytes = 1000
        current.tags = [:]
        gate.signal(); try await blocker.value; try await export.value
        let ids = Set(filter.matchingIDs(in: captured, root: 1))
        let expected = nativeLFText(captured, ids: ids, root: 1)
        XCTAssertEqual(try Data(contentsOf: output), Data(expected.utf8))
        XCTAssertEqual(captured.nodes[3].name, "한글🙂.bin")
    }
    func testConcurrentExclusiveWritersCommitOneCompleteResult() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let output = dir.appendingPathComponent("race.sns"); let snapshot = fixture()
        let results = await withTaskGroup(of: Bool.self) { group in
            for _ in 0..<8 {
                group.addTask {
                    do { try await ArtifactWorker().save(snapshot, to: output, replaceExisting: false); return true }
                    catch { return false }
                }
            }
            var values: [Bool] = []; for await result in group { values.append(result) }; return values
        }
        XCTAssertEqual(results.filter { $0 }.count, 1)
        XCTAssertEqual(try Data(contentsOf: output), try LegacyArtifactReference.encode(snapshot))
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["race.sns"])
    }
}
private final class FaultArtifactIO: ArtifactFileIO, @unchecked Sendable {
    private let native = NativeArtifactFileIO()
    private let lock = NSLock(); private var interrupted = false; private var written = 0
    let failAfter: Int?; let maxWrite: Int; let interruptFirst: Bool; let failWrite: Bool; let failClose: Bool; let failPublish: Bool; let zeroWrite: Bool
    init(maxWrite: Int = Int.max, failAfter: Int? = nil, interruptFirst: Bool = false, failWrite: Bool = false, failClose: Bool = false, failPublish: Bool = false, zeroWrite: Bool = false) {
        self.failAfter = failAfter; self.maxWrite = maxWrite; self.interruptFirst = interruptFirst; self.failWrite = failWrite
        self.failClose = failClose; self.failPublish = failPublish; self.zeroWrite = zeroWrite
    }
    func write(_ descriptor: Int32, bytes: UnsafeRawBufferPointer) throws -> Int {
        lock.lock(); let interrupt = interruptFirst && !interrupted; interrupted = true; let full = failAfter.map { written >= $0 } ?? false; lock.unlock()
        if interrupt { throw POSIXError(.EINTR) }
        if failWrite || full { throw POSIXError(.ENOSPC) }
        if zeroWrite { return 0 }
        let count = try native.write(descriptor, bytes: UnsafeRawBufferPointer(rebasing: bytes.prefix(min(maxWrite, bytes.count))))
        lock.lock(); written += count; lock.unlock(); return count
    }
    func close(_ descriptor: Int32) throws { try native.close(descriptor); if failClose { throw POSIXError(.EIO) } }
    func publish(_ temporary: String, to destination: String, replaceExisting: Bool) throws {
        if failPublish { throw POSIXError(.EACCES) }
        try native.publish(temporary, to: destination, replaceExisting: replaceExisting)
    }
}
