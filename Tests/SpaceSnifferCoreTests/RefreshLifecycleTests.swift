import XCTest
@testable import SpaceSnifferCore

final class RefreshLifecycleTests: XCTestCase, @unchecked Sendable {
    enum Failure: Error { case timeout }
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("refresh-lifetime-" + UUID().uuidString).resolvingSymlinksInPath()
        for i in 0..<48 {
            let dir = root.appendingPathComponent("branch-\(i)")
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            try Data([1]).write(to: dir.appendingPathComponent("event.bin"))
        }
        return root
    }
    private func eventually(_ condition: @escaping @Sendable () async -> Bool) async throws {
        for _ in 0..<400 { if await condition() { return }; try await Task.sleep(for: .milliseconds(20)) }
        throw Failure.timeout
    }
    private func settled(_ s: ScanSubscription, bytes: Int64? = nil) async throws -> ScanUpdate {
        try await withThrowingTaskGroup(of: ScanUpdate.self) { group in
            group.addTask {
                for await value in s.updates where !value.isScanning && !value.snapshot.nodes.isEmpty {
                    if bytes == nil || value.snapshot.nodes[0].logicalBytes == bytes { return value }
                }
                throw Failure.timeout
            }
            group.addTask { try await Task.sleep(for: .seconds(8)); throw Failure.timeout }
            defer { group.cancelAll() }; return try await group.next()!
        }
    }
    func testOldMonitorCallbackCannotQueueAfterReplacementOrRootRecreation() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let monitor = RetainedMonitorDeliveries(); let gate = RefreshScanGate(); defer { gate.release() }
        let admission = ScanAdmission(limit: 1); defer { admission.shutdown() }
        let service = ScanService(admission: admission, scanner: gate.scan, monitorFactory: { _, deliver in
            monitor.append(deliver); return NSObject()
        })
        let s = await service.subscribe(root, watching: true); _ = try await settled(s)
        let old = monitor.delivery(0)
        await service.setWatching(false, subscription: s); await service.setWatching(true, subscription: s)
        let current = monitor.delivery(1)
        gate.arm(); await service.rescan(rootPath: s.rootPath)
        try await eventually { gate.isBlocked }
        let events = (0..<48).map { PathChange(path: root.appendingPathComponent("branch-\($0)/event.bin").path, isDirectory: false, mustRescan: false) }
        await current(events)
        let observed = await service.pendingQueueObservation(rootPath: s.rootPath)
        let live = try XCTUnwrap(observed)
        XCTAssertEqual(live.count, 48); XCTAssertGreaterThan(live.slots, 0); XCTAssertFalse(live.storage.isReleased)
        let rootEvent = [PathChange(path: root.path, isDirectory: true, mustRescan: true)]
        await old(rootEvent)
        let unchanged = await service.pendingQueueObservation(rootPath: s.rootPath)
        XCTAssertEqual(unchanged?.count, 48) // stale root must not collapse unrelated current requests
        await service.stop(rootPath: s.rootPath)
        XCTAssertTrue(gate.wasCancelled); XCTAssertTrue(live.storage.isReleased)
        let cleared = await service.pendingQueueObservation(rootPath: s.rootPath)
        XCTAssertEqual(cleared?.count, 0); XCTAssertEqual(cleared?.slots, 0)
        gate.release(); _ = try await settled(s)
        await service.unsubscribe(s.id, rootPath: s.rootPath)
        let recreated = await service.subscribe(root, watching: true); _ = try await settled(recreated)
        let before = await service.statistics()
        await current(rootEvent) // same root string, obsolete Entry and monitor generation
        let after = await service.statistics()
        XCTAssertEqual(after.scanStarts, before.scanStarts)
        let empty = await service.pendingQueueObservation(rootPath: recreated.rootPath); XCTAssertEqual(empty?.count, 0)
        await service.unsubscribe(recreated.id, rootPath: recreated.rootPath)
    }
    func testRealFSEventsBurstCancelsRunningScanAndReleasesPromotedQueue() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let gate = RefreshScanGate(); defer { gate.release() }
        let admission = ScanAdmission(limit: 1); defer { admission.shutdown() }
        let service = ScanService(admission: admission, scanner: gate.scan)
        let s = await service.subscribe(root, watching: true); _ = try await settled(s)
        // Let creation events drain before editing existing files; no test event injection.
        try await Task.sleep(for: .milliseconds(300))
        gate.arm(); await service.rescan(rootPath: s.rootPath)
        try await eventually { gate.isBlocked }
        for i in 0..<48 { try Data([2, 3]).write(to: root.appendingPathComponent("branch-\(i)/event.bin")) }
        try await eventually { await service.pendingQueueObservation(rootPath: s.rootPath)?.count == 48 }
        let observed = await service.pendingQueueObservation(rootPath: s.rootPath)
        let live = try XCTUnwrap(observed)
        XCTAssertGreaterThan(live.slots, 0); XCTAssertFalse(live.storage.isReleased)
        let start = ContinuousClock.now
        let status = await service.statistics() // actor remains responsive while filesystem worker is blocked
        let duration = start.duration(to: .now).components
        let seconds = Double(duration.seconds) + Double(duration.attoseconds) / 1e18
        XCTAssertEqual(status.admission.active, 1)
        print("B08_LIVE pending=\(live.count) slots=\(live.slots) status_seconds=\(seconds)")
        await service.stop(rootPath: s.rootPath)
        XCTAssertTrue(gate.wasCancelled); XCTAssertTrue(live.storage.isReleased)
        let cleared = await service.pendingQueueObservation(rootPath: s.rootPath)
        XCTAssertEqual(cleared?.count, 0); XCTAssertEqual(cleared?.slots, 0)
        gate.release(); _ = try await settled(s)
        // Cancellation must not prevent a subsequent full refresh from converging.
        await service.rescan(rootPath: s.rootPath)
        let refreshed = try await settled(s, bytes: 96)
        XCTAssertEqual(refreshed.snapshot.fileCount, 48)
        let full = DiskScanner.scan(root)
        XCTAssertEqual(refreshed.snapshot.nodes[0].allocatedBytes, full.nodes[0].allocatedBytes)
        await service.unsubscribe(s.id, rootPath: s.rootPath)
        let empty = await service.statistics(); XCTAssertEqual(empty.roots, 0)
        print("B08_LIVE cancelled=true arena_released=true pending_after_stop=0 refreshed_bytes=96 roots_after_unsubscribe=0")
    }
}

private final class RetainedMonitorDeliveries: @unchecked Sendable {
    private let lock = NSLock(); private var values: [ScanService.MonitorDelivery] = []
    func append(_ value: @escaping ScanService.MonitorDelivery) { lock.lock(); values.append(value); lock.unlock() }
    func delivery(_ index: Int) -> ScanService.MonitorDelivery { lock.lock(); defer { lock.unlock() }; return values[index] }
}
private final class RefreshScanGate: @unchecked Sendable {
    private let lock = NSLock(); private let semaphore = DispatchSemaphore(value: 0)
    private var armed = false; private var control: ScanControl?
    func arm() { lock.lock(); armed = true; lock.unlock() }
    var isBlocked: Bool { lock.lock(); defer { lock.unlock() }; return control != nil }
    var wasCancelled: Bool { lock.lock(); let value = control; lock.unlock(); return value?.isCancelled == true }
    func release() { semaphore.signal() }
    func scan(_ url: URL, _ control: ScanControl, _ progress: (@Sendable (ScanSnapshot) -> Void)?, _ heartbeat: (@Sendable (ScanProgress) -> Void)?) -> ScanSnapshot {
        lock.lock(); let hold = armed; armed = false; if hold { self.control = control }; lock.unlock()
        if hold { _ = semaphore.wait(timeout: .now() + 12) }
        return DiskScanner.scan(url, control: control, progress: progress, heartbeat: heartbeat)
    }
}
