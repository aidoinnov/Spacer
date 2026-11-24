import XCTest
import Darwin
@testable import SpaceSnifferCore

final class ScanReviewFixTests: XCTestCase, @unchecked Sendable {
    private func listing(missing: Set<Int>) -> OrderedDirectoryListing {
        let entries = (0..<256).map { NativeDirectoryMetadata.Entry(name: String(format: "f%04d", $0),
            values: missing.contains($0) ? nil : NativeFileMetadata(stat()), directoryEntryCount: nil) }
        return .init(names: entries.map(\.name), entries: entries)
    }
    func testSparseCompletionObservesCancellationBeforeFirstStat() {
        let control = ScanControl(); control.cancel()
        let calls = ReviewCounter()
        let reader = MacDirectoryBatchReader(native: .orderedScan, statCall: { _,_ in calls.increment(); return -1 })
        let output = reader.completeMetadata(listing(missing: [1,65,129,193]), at: "/fixture", control: control)
        guard case .cancelled = output.value else { return XCTFail("no usable batch after cancellation") }
        XCTAssertEqual(calls.value, 0); XCTAssertEqual(output.statistics.statCalls, 0)
    }
    func testSparseCompletionStopsAfterStatThatRequestsCancellation() {
        let control = ScanControl(); let calls = ReviewCounter()
        let reader = MacDirectoryBatchReader(native: .orderedScan, statCall: { _,_ in
            calls.increment(); control.cancel(); errno = EIO; return -1
        })
        let output = reader.completeMetadata(listing(missing: [1,65,129,193]), at: "/fixture", control: control)
        guard case .cancelled = output.value else { return XCTFail("no usable batch after cancellation") }
        XCTAssertEqual(calls.value, 1); XCTAssertEqual(output.statistics.statCalls, 1)
    }
    func testCancelledCompletionDoesNotDependOnMissingDistribution() {
        for missing: Set<Int> in [[], [255], [0,64,128,192], [5,9,127], Set(0..<256)] {
            let control = ScanControl(); control.cancel(); let calls = ReviewCounter()
            let reader = MacDirectoryBatchReader(native: .orderedScan, statCall: { _,_ in calls.increment(); return -1 })
            let output = reader.completeMetadata(listing(missing: missing), at: "/fixture", control: control)
            guard case .cancelled = output.value else { return XCTFail("cancelled completion must not publish") }
            XCTAssertEqual(calls.value, 0)
        }
    }
    func testFailedFallbackKeepsNilMetadataAndActualAttemptCount() throws {
        let reader = MacDirectoryBatchReader(native: .orderedScan, statCall: { _,_ in errno = EACCES; return -1 })
        let output = reader.completeMetadata(listing(missing: [1]), at: "/fixture", control: ScanControl())
        guard case .listing(let value) = output.value else { return XCTFail("expected observed fallback") }
        XCTAssertNil(try XCTUnwrap(value.entries)[1].values); XCTAssertEqual(output.statistics.statCalls, 1)
    }
    func testRawSpellingDetectionAndCopyRemainIndependentOfStringEquality() {
        let a = DiskNode(id: 0, parent: nil, storedPath: NodePathStorage(base: "/", leaf: "cafe\u{301}"), name: "root")
        let b = DiskNode(id: 0, parent: nil, storedPath: NodePathStorage(base: "/", leaf: "café"), name: "root")
        XCTAssertEqual(a, b)
        var left = NodeTable([a]); let frozen = left
        XCTAssertEqual(left.differingNodeIDs(from: NodeTable([b]), control: ScanControl()), [0])
        left[0].path = "/changed"; XCTAssertEqual(frozen[0].path, "/cafe\u{301}")
    }
    func testEquivalentPathRepresentationsObeyEqualityLawsAndNodeWireContract() throws {
        let paths = [NodePathStorage(base: "/foo", leaf: "bar"), NodePathStorage(base: "/foo/", leaf: "bar"),
                     NodePathStorage(wrappedValue: "/foo/bar")]
        let encoder = JSONEncoder(); encoder.outputFormatting = .sortedKeys
        for a in paths { for b in paths {
            XCTAssertEqual(a, b); XCTAssertEqual(b, a); XCTAssertEqual(a, a)
            let left = DiskNode(id: 1, parent: 0, storedPath: a, name: "bar")
            let right = DiskNode(id: 1, parent: 0, storedPath: b, name: "bar")
            XCTAssertEqual(left, right); XCTAssertEqual(try encoder.encode(left), try encoder.encode(right))
            for c in paths { if a == b && b == c { XCTAssertEqual(a, c) } }
        } }
        XCTAssertNotEqual(NodePathStorage(base: "/foo//", leaf: "bar"), paths[0])
        XCTAssertNotEqual(NodePathStorage(wrappedValue: "/foo/"), NodePathStorage(wrappedValue: "/foo"))
        XCTAssertEqual(NodePathStorage(base: "/", leaf: "한글"), NodePathStorage(wrappedValue: "/한글"))
        XCTAssertEqual(NodePathStorage(base: "/cafe\u{301}", leaf: "x"), NodePathStorage(wrappedValue: "/café/x"))
        for literal in ["C:\\folder\\file", "\\\\server\\share\\file"] {
            var value = paths[0]; value.wrappedValue = literal
            XCTAssertEqual(value, NodePathStorage(wrappedValue: literal))
        }
    }
    func testActualReaderPoolCancelsAfterInFlightSparseStatAndReleasesPermit() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/review-sparse-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: root) }
        for i in 0..<256 { try Data([1]).write(to: root.appendingPathComponent(String(format: "f%04d", i))) }
        let native = NativeDirectoryMetadata(call: { fd, attrs, buffer, bytes, flags in
            let count = getattrlistbulk(fd, &attrs, buffer, bytes, flags)
            var offset = 0
            for _ in 0..<max(0, count) {
                let length = Int(buffer.loadUnaligned(fromByteOffset: offset, as: UInt32.self))
                let ref = buffer.loadUnaligned(fromByteOffset: offset+28, as: attrreference_t.self)
                let ptr = buffer.advanced(by: offset+28+Int(ref.attr_dataoffset)).assumingMemoryBound(to: CChar.self)
                let name = String(cString: ptr)
                if ["f0001","f0065","f0129","f0193"].contains(name) {
                    buffer.storeBytes(of: UInt32(EACCES), toByteOffset: offset+24, as: UInt32.self)
                }
                offset += length
            }
            return count
        })
        let entered = expectation(description: "first fallback stat entered")
        let gate = DispatchSemaphore(value: 0); defer { gate.signal() }
        let calls = ReviewCounter(); let control = ScanControl()
        let reader = MacDirectoryBatchReader(native: native, statCall: { path, value in
            if calls.next() == 1 { entered.fulfill(); _ = gate.wait(timeout: .now()+5) }
            return lstat(path, &value)
        })
        let budget = DirectoryIOBudget(limit: 1)
        let pool = DirectoryReadPool(workers: 1, capacity: 1, budget: budget); defer { pool.shutdown() }
        let ticket = try XCTUnwrap(pool.submit(reader: reader, path: root.path, control: control))
        await fulfillment(of: [entered], timeout: 4)
        XCTAssertEqual(budget.observation.active, 1)
        control.cancel(); pool.cancelQueued(control: control); gate.signal()
        let output = ticket.wait()
        guard case .cancelled = output.value else { return XCTFail("cancelled batch must not escape") }
        XCTAssertEqual(calls.value, 1); XCTAssertEqual(output.statistics.statCalls, 1)
        XCTAssertEqual(budget.observation.active, 0)
    }
}

private final class ReviewCounter: @unchecked Sendable {
    private let lock = NSLock(); private var count = 0
    func increment() { lock.withLock { count += 1 } }
    func next() -> Int { lock.withLock { count += 1; return count } }
    var value: Int { lock.withLock { count } }
}
