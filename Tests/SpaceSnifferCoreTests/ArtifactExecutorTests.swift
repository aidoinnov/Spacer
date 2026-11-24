import XCTest
@testable import SpaceSnifferCore

final class ArtifactExecutorTests: XCTestCase, @unchecked Sendable {
    func testBoundedQueueAllowsActorToRejectWhileAnotherOperationIsBlocked() async throws {
        let executor = ArtifactIOExecutor(capacity: 1)
        let worker = ArtifactWorker(executor: executor)
        let gate = DispatchSemaphore(value: 0); defer { gate.signal() }
        let started = expectation(description: "I/O queue blocked")
        let blocker = Task { try await executor.run { started.fulfill(); gate.wait() } }
        await fulfillment(of: [started], timeout: 3)
        let dir = FileManager.default.temporaryDirectory.appendingPathComponent("artifact-queue-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: dir) }
        let source = ScanSnapshot(rootPath: "/r", nodes: [DiskNode(id: 0, parent: nil, path: "/r", name: "r", isDirectory: true)])
        let file = dir.appendingPathComponent("input.sns"); try SNSSnapshot.encode(source).write(to: file)
        let load = Task { try await worker.load(file) }
        for _ in 0..<3000 {
            if executor.outstandingCount == 2 { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(executor.outstandingCount, 2)
        let rejected = expectation(description: "actor remains responsive while load awaits its queue")
        let excess = Task {
            do { _ = try await worker.volumes(); XCTFail("queue should reject before I/O starts") }
            catch ArtifactIOError.busy { rejected.fulfill() }
            catch { XCTFail("unexpected error: \(error)") }
        }
        await fulfillment(of: [rejected], timeout: 3)
        gate.signal(); try await blocker.value; await excess.value
        let result = try await load.value; XCTAssertEqual(result.rootPath, "/r")
        XCTAssertEqual(executor.outstandingCount, 0)
    }
    func testBlockedOutputDoesNotPreventIndependentScanAndStateQueries() async throws {
        let base = FileManager.default.temporaryDirectory.appendingPathComponent("artifact-scan-" + UUID().uuidString).resolvingSymlinksInPath()
        let input = base.appendingPathComponent("input")
        try FileManager.default.createDirectory(at: input, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: base) }
        try Data([1, 2, 3]).write(to: input.appendingPathComponent("data.bin"))
        let frozen = DiskScanner.scan(input)
        let started = expectation(description: "artifact write is blocked")
        let gate = DispatchSemaphore(value: 0); defer { gate.signal() }
        let io = BlockingArtifactIO(started: { started.fulfill() }, gate: gate)
        let executor = ArtifactIOExecutor()
        let export = Task {
            try await executor.run {
                try ArtifactTransfer.save(frozen, ids: nil, root: 0, to: base.appendingPathComponent("saved.sns"), replaceExisting: false, io: io)
            }
        }
        await fulfillment(of: [started], timeout: 3)
        let admission = ScanAdmission(limit: 1); defer { admission.shutdown() }
        let service = ScanService(admission: admission)
        let subscription = await service.subscribe(input, watching: false)
        let scanned = try await withThrowingTaskGroup(of: ScanSnapshot.self) { group in
            group.addTask {
                for await value in subscription.updates where !value.isScanning { return value.snapshot }
                throw CancellationError()
            }
            group.addTask { try await Task.sleep(for: .seconds(3)); throw CancellationError() }
            defer { group.cancelAll() }; return try await group.next()!
        }
        XCTAssertEqual(scanned.fileCount, 1); XCTAssertEqual(scanned.nodes[0].logicalBytes, 3)
        let stats = await service.statistics(); XCTAssertEqual(stats.roots, 1)
        XCTAssertEqual(executor.outstandingCount, 1)
        await service.unsubscribe(subscription.id, rootPath: subscription.rootPath)
        gate.signal(); try await export.value
        XCTAssertEqual(try Data(contentsOf: base.appendingPathComponent("saved.sns")), try LegacyArtifactReference.encode(frozen))
    }
    func testCompletedQueueOperationReleasesCapturedInputWhenIdle() async throws {
        let executor = ArtifactIOExecutor()
        let released = expectation(description: "input released")
        func enqueue() async throws {
            let capture = ArtifactLifetime { released.fulfill() }
            let value = try await executor.run { [capture] in capture.value }
            XCTAssertEqual(value, 7)
        }
        try await enqueue()
        await fulfillment(of: [released], timeout: 3)
        XCTAssertEqual(executor.outstandingCount, 0)
    }
}
private final class ArtifactLifetime: @unchecked Sendable {
    let value = 7; let release: @Sendable () -> Void
    init(_ release: @escaping @Sendable () -> Void) { self.release = release }
    deinit { release() }
}

private final class BlockingArtifactIO: ArtifactFileIO, @unchecked Sendable {
    private let native = NativeArtifactFileIO(); private let lock = NSLock(); private var first = true
    private let started: @Sendable () -> Void; private let gate: DispatchSemaphore
    init(started: @escaping @Sendable () -> Void, gate: DispatchSemaphore) { self.started = started; self.gate = gate }
    func write(_ descriptor: Int32, bytes: UnsafeRawBufferPointer) throws -> Int {
        lock.lock(); let block = first; first = false; lock.unlock()
        if block { started(); gate.wait() }
        return try native.write(descriptor, bytes: bytes)
    }
    func close(_ descriptor: Int32) throws { try native.close(descriptor) }
    func publish(_ temporary: String, to destination: String, replaceExisting: Bool) throws {
        try native.publish(temporary, to: destination, replaceExisting: replaceExisting)
    }
}
