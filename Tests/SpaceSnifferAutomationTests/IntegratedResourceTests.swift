import XCTest
import Darwin
import SnifferTestSupport
import SpaceSnifferAutomation
@testable import SpaceSnifferCore

final class IntegratedResourceTests: XCTestCase, @unchecked Sendable {
    private enum Failure: Error { case timeout, ended }
    private func wait(_ s: ScanSubscription, predicate: @escaping @Sendable (ScanUpdate) -> Bool) async throws -> ScanUpdate {
        try await withThrowingTaskGroup(of: ScanUpdate.self) { group in
            group.addTask { for await update in s.updates where predicate(update) { return update }; throw Failure.ended }
            group.addTask { try await Task.sleep(for: .seconds(10)); throw Failure.timeout }
            defer { group.cancelAll() }; return try await group.next()!
        }
    }
    func testActualRunningScanThreadsDoNotStarveMetricsFilterOrGeometry() async throws {
        let admission = ScanAdmission(limit: 8, capacity: 64); defer { admission.shutdown() }
        let gate = DispatchSemaphore(value: 0); defer { for _ in 0..<8 { gate.signal() } }
        let running = expectation(description: "eight native I/O workers"); running.expectedFulfillmentCount = 8
        let completed = expectation(description: "running workers all exit"); completed.expectedFulfillmentCount = 8
        let ids = ThreadIDs(); let snapshot = OptimizationFixture.metadata(files: 2000)
        for _ in 0..<8 {
            try admission.submit(control: ScanControl(), operation: {
                var id: UInt64 = 0; pthread_threadid_np(nil, &id); ids.add(String(id)); running.fulfill()
                _ = gate.wait(timeout: .now() + 12); return snapshot
            }, completion: { _ in completed.fulfill() })
        }
        await fulfillment(of: [running], timeout: 5)
        XCTAssertEqual(admission.statistics().active, 8)
        let start = DispatchTime.now().uptimeNanoseconds
        async let metrics = ProcessMetrics.readAsync()
        async let filtered = Task.detached { try ScanFilter("*.bin").weights(in: snapshot, mode: .logical) }.value
        async let geometry = Task.detached {
            let weights = try! ScanFilter("").weights(in: snapshot, mode: .logical)
            return GeometrySession().tiles(source: GeometrySource(snapshot: snapshot, weights: weights), root: 0, depth: 2, selected: nil,
                in: CGRect(x: 0, y: 0, width: 1000, height: 600), control: ScanControl())
        }.value
        let result = try await metrics; let weights = try await filtered; let tiles = await geometry
        XCTAssertFalse(weights.isEmpty); XCTAssertNotNil(tiles)
        let object = try XCTUnwrap(result.object)
        XCTAssertEqual(object["sampling_on_main_thread"]?.boolean, false)
        XCTAssertGreaterThanOrEqual(object["thread_count"]?.integer ?? 0, 8)
        let sampled = object["sampled_thread_states"]!
        let data = try JSONEncoder().encode(sampled)
        let states = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
        var workers = states.filter { ids.values.contains($0["id"] as? String ?? "") }
        // Fulfillment happens immediately before the semaphore wait. Sampling
        // can catch that transition; wait for the observed kernel state rather
        // than equating "started" with "already sleeping" under host load.
        for _ in 0..<20 {
            if workers.count == 8 && workers.allSatisfy({ ($0["run_state"] as? Int ?? -1) == Int(TH_STATE_WAITING) }) { break }
            try await Task.sleep(for: .milliseconds(20))
            let retry = try await ProcessMetrics.readAsync()
            let sampled = try XCTUnwrap(retry.object?["sampled_thread_states"])
            let data = try JSONEncoder().encode(sampled)
            let states = try JSONSerialization.jsonObject(with: data) as! [[String: Any]]
            workers = states.filter { ids.values.contains($0["id"] as? String ?? "") }
        }
        XCTAssertEqual(workers.count, 8)
        XCTAssertTrue(workers.allSatisfy { ($0["run_state"] as? Int ?? -1) == Int(TH_STATE_WAITING) }, "Worker states: \(workers)")
        let elapsed = Double(DispatchTime.now().uptimeNanoseconds &- start) / 1e9
        XCTAssertLessThan(elapsed, 8) // The native gates are still closed, not a timing improvement assertion.
        XCTAssertEqual(admission.statistics().active, 8)
        print("RESOURCE_GATE native_workers=8 metrics_seconds=\(elapsed) os_threads=\(object["thread_count"]!.integer!) sampled_waiting=\(workers.count)")
        for _ in 0..<8 { gate.signal() }; await fulfillment(of: [completed], timeout: 5)
        XCTAssertEqual(admission.statistics().active, 0)
    }
    func testActualScopedNewCycleAndFrozenQueryExportReaders() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sniffer-integrated-" + UUID().uuidString).resolvingSymlinksInPath()
        defer { try? FileManager.default.removeItem(at: root) }
        try OptimizationFixture.disk(at: root, branches: 3)
        let scanGate = OneScanGate(); defer { scanGate.release() }
        let service = ScanService(scanner: { url, control, progress, heartbeat in
            scanGate.waitIfArmed()
            return DiskScanner.scan(url, control: control, progress: progress, heartbeat: heartbeat)
        })
        let lease = await service.subscribe(root, watching: false)
        let initial = try await wait(lease) { !$0.isScanning && !$0.snapshot.nodes.isEmpty }
        let frozen = initial.snapshot; let bytes = try SNSSnapshot.encode(frozen)
        let filter = try ScanFilter(""); let weights = filter.weights(in: frozen, mode: .logical)
        let query = QueryContext(snapshot: frozen, weights: weights, filter: filter, mode: .logical, showHidden: true, revision: "frozen", focus: 0, selection: nil)
        let read = Task.detached { for _ in 0..<20 { _ = try query.query(command: "tree_children", arguments: ["limit": .int(10)]) }; return try SNSSnapshot.encode(query.snapshot) }
        let target = root.appendingPathComponent("branch-0"); try Data([9,8,7]).write(to: target.appendingPathComponent("new.bin"))
        scanGate.arm(); await service.rescan(rootPath: lease.rootPath, scope: target.path)
        let scanning = try await wait(lease) { $0.isScanning && $0.scope == target.path }
        scanGate.release()
        let current = try await wait(lease) { !$0.isScanning && $0.revision > initial.revision && $0.scope == target.path && $0.snapshot.nodes.contains { $0.name == "new.bin" } }
        XCTAssertGreaterThanOrEqual(current.revision, scanning.revision)
        let full = DiskScanner.scan(root)
        XCTAssertEqual(current.snapshot.nodes[0].logicalBytes, full.nodes[0].logicalBytes)
        XCTAssertEqual(current.snapshot.nodes[0].allocatedBytes, full.nodes[0].allocatedBytes)
        XCTAssertTrue(current.snapshot.nodes.contains { $0.path.hasSuffix("branch-2/café.txt") })
        let oldData = try await read.value; XCTAssertEqual(oldData, bytes); XCTAssertEqual(try SNSSnapshot.encode(frozen), bytes)
        let exported = root.deletingLastPathComponent().appendingPathComponent("sniffer-export-" + UUID().uuidString + ".sns")
        defer { try? FileManager.default.removeItem(at: exported) }
        try await ArtifactWorker.shared.save(frozen, to: exported)
        let loaded = try await ArtifactWorker.shared.load(exported)
        // SNS reload assigns traversal IDs; path/size and encoded native bytes are invariant.
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: loaded.nodes.map { ($0.path, $0.logicalBytes) }), Dictionary(uniqueKeysWithValues: frozen.nodes.map { ($0.path, $0.logicalBytes) }))
        XCTAssertEqual(try SNSSnapshot.encode(loaded), bytes)
        await service.unsubscribe(lease.id, rootPath: lease.rootPath)
        let empty = await service.statistics(); XCTAssertEqual(empty.roots, 0)
        print("RESOURCE_SCOPE initial_revision=\(initial.revision) scanning_revision=\(scanning.revision) final_revision=\(current.revision) scope_verified=true frozen_query_export=true")
    }
    func testMetadataResolutionIsOffActorAndCancellationDoesNotLaunchRoot() async throws {
        let gate = DispatchSemaphore(value: 0); let entered = expectation(description: "metadata I/O gate")
        let blocker = Task { try await PathIO.executor.run { entered.fulfill(); _ = gate.wait(timeout: .now()+10); return 0 } }
        defer { gate.signal() }
        await fulfillment(of: [entered], timeout: 3)
        let service = ScanService()
        let task = Task { await service.subscribe(FileManager.default.temporaryDirectory, watching: false) }
        try await Task.sleep(for: .milliseconds(20)); task.cancel()
        let stats = await service.statistics(); XCTAssertEqual(stats.roots, 0); XCTAssertEqual(stats.scanStarts, 0)
        let metrics = try await ProcessMetrics.readAsync(); XCTAssertNotNil(metrics.object?["thread_count"])
        gate.signal(); _ = try await blocker.value
        let cancelled = await task.value
        let update = try await wait(cancelled) { !$0.isScanning }
        XCTAssertTrue(update.snapshot.cancelled)
        let final = await service.statistics(); XCTAssertEqual(final.roots, 0); XCTAssertEqual(final.scanStarts, 0)
    }
}
private final class ThreadIDs: @unchecked Sendable {
    private let lock = NSLock(); private var storage = Set<String>()
    func add(_ value: String) { _ = lock.withLock { storage.insert(value) } }
    var values: Set<String> { lock.withLock { storage } }
}
private final class OneScanGate: @unchecked Sendable {
    private let lock = NSLock(); private let semaphore = DispatchSemaphore(value: 0); private var armed = false
    func arm() { lock.withLock { armed = true } }
    func release() { semaphore.signal() }
    func waitIfArmed() {
        let wait = lock.withLock { let old = armed; armed = false; return old }
        if wait { _ = semaphore.wait(timeout: .now()+10) }
    }
}
