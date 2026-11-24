import XCTest
@testable import SpaceSnifferCore

final class ScanSchedulingTests: XCTestCase, @unchecked Sendable {
    func testRunningOldRootCompletionCannotMutateRecreatedEntry() async throws {
        let root = try fixtures(); defer { try? FileManager.default.removeItem(at: root) }
        let gate = DispatchSemaphore(value: 0); defer { gate.signal() }
        let started = expectation(description: "old running native scan")
        let oldFinished = expectation(description: "old scan exits")
        let calls = ScanCalls(); let admission = ScanAdmission(limit: 2); defer { admission.shutdown() }
        let service = ScanService(admission: admission, scanner: { url, control, progress, heartbeat in
            let number = calls.addReturningCount(url.path)
            if number == 1 {
                let frozen = DiskScanner.scan(url); started.fulfill(); _ = gate.wait(timeout: .now()+5)
                oldFinished.fulfill(); return frozen // Deliberately ignores cancellation: publication must still reject it.
            }
            return DiskScanner.scan(url, control: control, progress: progress, heartbeat: heartbeat)
        })
        let url = root.appendingPathComponent("first")
        let old = await service.subscribe(url, watching: false); await fulfillment(of: [started], timeout: 2)
        await service.unsubscribe(old.id, rootPath: old.rootPath)
        try Data([8,9]).write(to: url.appendingPathComponent("new.bin"))
        let fresh = await service.subscribe(url, watching: false)
        let current = try await update(fresh) { !$0.isScanning && $0.snapshot.fileCount == 2 }
        gate.signal(); await fulfillment(of: [oldFinished], timeout: 2)
        // Actor FIFO barrier after the completion Task has had a chance to enqueue.
        try await Task.sleep(for: .milliseconds(30))
        let same = await service.subscribe(url, watching: false)
        let latest = try await update(same) { !$0.isScanning }
        XCTAssertEqual(latest.snapshot.fileCount, 2); XCTAssertEqual(latest.snapshot.nodes[0].logicalBytes, current.snapshot.nodes[0].logicalBytes)
        XCTAssertEqual(calls.values().count, 2)
        await service.unsubscribe(fresh.id, rootPath: fresh.rootPath); await service.unsubscribe(same.id, rootPath: same.rootPath)
        let stats = await service.statistics(); XCTAssertEqual(stats.roots, 0)
    }
    private enum WaitError: Error { case timeout, ended }
    private func update(_ s: ScanSubscription, where predicate: @escaping @Sendable (ScanUpdate) -> Bool) async throws -> ScanUpdate {
        try await withThrowingTaskGroup(of: ScanUpdate.self) { group in
            group.addTask { for await value in s.updates where predicate(value) { return value }; throw WaitError.ended }
            group.addTask { try await Task.sleep(for: .seconds(8)); throw WaitError.timeout }
            defer { group.cancelAll() }; return try await group.next()!
        }
    }
    private func fixtures() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sniffer-admission-" + UUID().uuidString).resolvingSymlinksInPath()
        for name in ["first", "second"] {
            try FileManager.default.createDirectory(at: root.appendingPathComponent(name), withIntermediateDirectories: true)
            try Data([1, 2, 3]).write(to: root.appendingPathComponent(name + "/data.bin"))
        }
        return root
    }
    func testQueuedRootUnsubscribeAndNewGenerationCannotPublishOldCancellation() async throws {
        let root = try fixtures(); defer { try? FileManager.default.removeItem(at: root) }
        let gate = DispatchSemaphore(value: 0); let started = expectation(description: "first filesystem started")
        let calls = ScanCalls(); let admission = ScanAdmission(limit: 1); defer { admission.shutdown() }
        let service = ScanService(admission: admission, scanner: { url, control, progress, heartbeat in
            calls.add(url.lastPathComponent)
            if url.lastPathComponent == "first" { started.fulfill(); gate.wait() }
            return DiskScanner.scan(url, control: control, progress: progress, heartbeat: heartbeat)
        })
        let first = await service.subscribe(root.appendingPathComponent("first"), watching: false)
        await fulfillment(of: [started], timeout: 3)
        let old = await service.subscribe(root.appendingPathComponent("second"), watching: false)
        XCTAssertEqual(admission.statistics().queued, 1)
        await service.unsubscribe(old.id, rootPath: old.rootPath)
        XCTAssertEqual(admission.statistics().queued, 0)
        let current = await service.subscribe(root.appendingPathComponent("second"), watching: false)
        gate.signal()
        let result = try await update(current) { !$0.isScanning && $0.snapshot.fileCount == 1 }
        XCTAssertFalse(result.snapshot.cancelled); XCTAssertEqual(result.snapshot.nodes[0].logicalBytes, 3)
        XCTAssertEqual(calls.values(), ["first", "second"])
        await service.unsubscribe(first.id, rootPath: first.rootPath); await service.unsubscribe(current.id, rootPath: current.rootPath)
    }
    func testQueuedRescanReplacesPendingJobWithoutStartingObsoleteIO() async throws {
        let root = try fixtures(); defer { try? FileManager.default.removeItem(at: root) }
        let gate = DispatchSemaphore(value: 0); let started = expectation(description: "blocking first scan")
        let calls = ScanCalls(); let admission = ScanAdmission(limit: 1); defer { admission.shutdown() }
        let service = ScanService(admission: admission, scanner: { url, control, progress, heartbeat in
            calls.add(url.lastPathComponent)
            if url.lastPathComponent == "first" { started.fulfill(); gate.wait() }
            return DiskScanner.scan(url, control: control, progress: progress, heartbeat: heartbeat)
        })
        let first = await service.subscribe(root.appendingPathComponent("first"), watching: false)
        await fulfillment(of: [started], timeout: 3)
        let second = await service.subscribe(root.appendingPathComponent("second"), watching: false)
        await service.rescan(rootPath: second.rootPath)
        // Observe the cancellation/restart cycle before releasing unrelated I/O.
        _ = try await update(second) { $0.isScanning && $0.revision > 0 }
        XCTAssertEqual(calls.values(), ["first"])
        gate.signal()
        let result = try await update(second) { !$0.isScanning && $0.snapshot.fileCount == 1 }
        XCTAssertEqual(result.snapshot.nodes[0].logicalBytes, 3); XCTAssertFalse(result.snapshot.cancelled)
        XCTAssertEqual(calls.values(), ["first", "second"])
        await service.unsubscribe(first.id, rootPath: first.rootPath); await service.unsubscribe(second.id, rootPath: second.rootPath)
    }
    func testAdmissionOverflowIsReportedWithoutFilesystemIssueOrStuckScanning() async throws {
        let root = try fixtures(); defer { try? FileManager.default.removeItem(at: root) }
        let gate = DispatchSemaphore(value: 0); let started = expectation(description: "running")
        let calls = ScanCalls(); let admission = ScanAdmission(limit: 1, capacity: 0); defer { admission.shutdown() }
        let service = ScanService(admission: admission, scanner: { url, control, progress, heartbeat in
            calls.add(url.lastPathComponent); started.fulfill(); gate.wait()
            return DiskScanner.scan(url, control: control, progress: progress, heartbeat: heartbeat)
        })
        let first = await service.subscribe(root.appendingPathComponent("first"), watching: false)
        await fulfillment(of: [started], timeout: 3)
        let second = await service.subscribe(root.appendingPathComponent("second"), watching: false)
        let rejected = try await update(second) { !$0.isScanning }
        XCTAssertNotNil(rejected.schedulingError); XCTAssertEqual(rejected.snapshot.issueCount, 0)
        XCTAssertEqual(calls.values(), ["first"])
        gate.signal()
        _ = try await update(first) { !$0.isScanning && $0.snapshot.fileCount == 1 }
        await service.unsubscribe(first.id, rootPath: first.rootPath); await service.unsubscribe(second.id, rootPath: second.rootPath)
    }
}
private final class ScanCalls: @unchecked Sendable {
    private let lock = NSLock(); private var names: [String] = []
    func add(_ name: String) { lock.lock(); names.append(name); lock.unlock() }
    func addReturningCount(_ name: String) -> Int { lock.withLock { names.append(name); return names.count } }
    func values() -> [String] { lock.lock(); defer { lock.unlock() }; return names }
}
