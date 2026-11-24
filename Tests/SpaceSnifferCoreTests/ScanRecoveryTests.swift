import XCTest
import Darwin
@testable import SpaceSnifferCore

final class ScanRecoveryTests: XCTestCase, @unchecked Sendable {
    private enum Failure: Error { case timeout, ended }
    private func update(_ subscription: ScanSubscription, where predicate: @escaping @Sendable (ScanUpdate) -> Bool) async throws -> ScanUpdate {
        try await withThrowingTaskGroup(of: ScanUpdate.self) { group in
            group.addTask { for await value in subscription.updates where predicate(value) { return value }; throw Failure.ended }
            group.addTask { try await Task.sleep(for: .seconds(8)); throw Failure.timeout }
            defer { group.cancelAll() }; return try await group.next()!
        }
    }
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("scan-recovery-" + UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a"), withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("a/old.bin"))
        try Data([4, 5]).write(to: root.appendingPathComponent("sibling.bin"))
        return root
    }
    func testCancelledScopedAndRootRescansRetainBaselineAndCancellation() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let original = DiskScanner.scan(root)
        for scope in [root.path, root.appendingPathComponent("a").path] {
            let control = ScanControl()
            let result = ScanWork.run(original: original, scope: scope, control: control, scanner: { url, control, _, _ in
                var partial = DiskScanner.scan(url); partial.nodes[0].logicalBytes = 0
                control.cancel(); partial.cancelled = true; return partial
            }, progress: { _ in }, heartbeat: { _ in })
            XCTAssertTrue(result.cancelled); XCTAssertNotNil(result.finished)
            XCTAssertEqual(Array(result.nodes), Array(original.nodes)); XCTAssertEqual(result.rootPath, original.rootPath)
            XCTAssertEqual(result.fileCount, original.fileCount); XCTAssertEqual(original.nodes[0].logicalBytes, 5)
        }
        let empty = ScanSnapshot(rootPath: root.path); let stopped = ScanControl()
        let partial = ScanWork.run(original: empty, scope: root.path, control: stopped, scanner: { url, control, _, _ in
            let value = DiskScanner.scan(url, control: control, heartbeat: { _ in control.cancel() }); return value
        }, progress: { _ in }, heartbeat: { _ in })
        XCTAssertTrue(partial.cancelled); XCTAssertEqual(partial.nodes.count, 1)
    }
    func testTruncatedIssuesRequireRootRefreshAndCannotBeSilentlyMerged() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var original = DiskScanner.scan(root)
        original.issues = (0..<500).map { root.appendingPathComponent("unseen/\($0)").path + ": denied" }
        original.issueCount = 502
        let branch = DiskScanner.scan(root.appendingPathComponent("a"))
        XCTAssertNil(SnapshotTree.replacing(original, with: branch, control: ScanControl()))
        let calls = RecoveryPaths()
        let result = ScanWork.run(original: original, scope: branch.rootPath, control: ScanControl(), scanner: { url, control, progress, heartbeat in
            calls.append(url.path); return DiskScanner.scan(url, control: control, progress: progress, heartbeat: heartbeat)
        }, progress: { _ in }, heartbeat: { _ in })
        XCTAssertEqual(calls.values, [root.path]); XCTAssertEqual(result.issueCount, 0)
        XCTAssertEqual(result.fileCount, 2); XCTAssertEqual(result.nodes[0].logicalBytes, 5)
    }
    func testUnreadableAndRemovedDirectoriesAreIssuesNotInventedFreeSpace() throws {
        if getuid() == 0 { throw XCTSkip("root bypasses POSIX directory permission fixture") }
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let blocked = root.appendingPathComponent("a")
        XCTAssertEqual(chmod(blocked.path, 0), 0)
        defer { _ = chmod(blocked.path, 0o700) }
        let denied = DiskScanner.scan(root)
        XCTAssertEqual(denied.issueCount, 1); XCTAssertEqual(denied.fileCount, 1)
        XCTAssertEqual(denied.nodes[0].logicalBytes, 2)
        XCTAssertNotNil(denied.nodes.first(where: { $0.path == blocked.path })?.issue)
        XCTAssertFalse(denied.nodes.contains { [4, 5, 6].contains($0.nativeType) })
        _ = chmod(blocked.path, 0o700)
        let deleted = DiskScanner.scan(root, heartbeat: { value in
            if value.visitedFolders == 0 { try? FileManager.default.removeItem(at: root) }
        })
        XCTAssertEqual(deleted.issueCount, 1); XCTAssertEqual(deleted.nodes.count, 1)
        XCTAssertNotNil(deleted.nodes.first?.issue); XCTAssertFalse(deleted.cancelled)
        let stopped = ScanControl(); stopped.cancel()
        let absent = DiskScanner.scan(root, control: stopped)
        XCTAssertTrue(absent.cancelled); XCTAssertEqual(absent.issueCount, 1); XCTAssertNotNil(absent.finished)
    }
    func testStopOfRunningScopedScanPublishesCancelledWholeRoot() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let gate = DispatchSemaphore(value: 0); defer { gate.signal() }
        let entered = expectation(description: "scoped scan running")
        let admission = ScanAdmission(limit: 1); defer { admission.shutdown() }
        let service = ScanService(admission: admission, scanner: { url, control, progress, heartbeat in
            let result = DiskScanner.scan(url, control: control, progress: progress, heartbeat: heartbeat)
            if url.lastPathComponent == "a" { entered.fulfill(); _ = gate.wait(timeout: .now()+5) }
            return result
        })
        let subscription = await service.subscribe(root, watching: false)
        let initial = try await update(subscription) { !$0.isScanning && $0.snapshot.fileCount == 2 }
        await service.rescan(rootPath: subscription.rootPath, scope: root.appendingPathComponent("a").path)
        await fulfillment(of: [entered], timeout: 3)
        await service.stop(rootPath: subscription.rootPath); gate.signal()
        let stopped = try await update(subscription) { !$0.isScanning && $0.snapshot.cancelled }
        XCTAssertEqual(Array(stopped.snapshot.nodes), Array(initial.snapshot.nodes))
        XCTAssertEqual(stopped.snapshot.rootPath, root.path); XCTAssertEqual(stopped.snapshot.nodes[0].logicalBytes, 5)
        let statistics = await service.statistics(); XCTAssertEqual(statistics.admission.active, 0); XCTAssertEqual(statistics.admission.queued, 0)
        await service.unsubscribe(subscription.id, rootPath: subscription.rootPath)
    }
    func testTruncatedIssuesEscalateAdvertisedServiceScopeAsWellAsWork() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let calls = RecoveryPaths(); let admission = ScanAdmission(limit: 1); defer { admission.shutdown() }
        let service = ScanService(admission: admission, scanner: { url, control, progress, heartbeat in
            calls.append(url.path)
            var result = DiskScanner.scan(url, control: control, progress: progress, heartbeat: heartbeat)
            if calls.values.count == 1 {
                result.issues = (0..<500).map { root.appendingPathComponent("unseen/\($0)").path + ": denied" }
                result.issueCount = 502
            }
            return result
        })
        let subscription = await service.subscribe(root, watching: false)
        let first = try await update(subscription) { !$0.isScanning && $0.snapshot.issueCount == 502 }
        await service.rescan(rootPath: subscription.rootPath, scope: root.appendingPathComponent("a").path)
        let refreshed = try await update(subscription) { !$0.isScanning && $0.revision > first.revision && $0.snapshot.issueCount == 0 }
        XCTAssertEqual(refreshed.scope, root.path); XCTAssertEqual(calls.values, [root.path, root.path])
        XCTAssertEqual(refreshed.snapshot.nodes[0].logicalBytes, 5)
        await service.unsubscribe(subscription.id, rootPath: subscription.rootPath)
    }
    func testDroppedEventDuringRunningScopedScanConvergesByRootRefresh() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let gate = DispatchSemaphore(value: 0); defer { gate.signal() }
        let entered = expectation(description: "old branch snapshot in flight")
        let delivery = RecoveryMonitor(); let calls = RecoveryPaths()
        let admission = ScanAdmission(limit: 1); defer { admission.shutdown() }
        let service = ScanService(admission: admission, scanner: { url, control, progress, heartbeat in
            calls.append(url.path)
            let result = DiskScanner.scan(url, control: control, progress: progress, heartbeat: heartbeat)
            if url.lastPathComponent == "a" { entered.fulfill(); _ = gate.wait(timeout: .now()+5) }
            return result
        }, monitorFactory: { _, callback in delivery.set(callback); return NSObject() })
        let subscription = await service.subscribe(root, watching: true)
        let initial = try await update(subscription) { !$0.isScanning && $0.snapshot.fileCount == 2 }
        let frozen = initial.snapshot
        await service.rescan(rootPath: subscription.rootPath, scope: root.appendingPathComponent("a").path)
        await fulfillment(of: [entered], timeout: 3)
        try FileManager.default.removeItem(at: root.appendingPathComponent("a/old.bin"))
        try Data(repeating: 1, count: 10).write(to: root.appendingPathComponent("a/new.bin"))
        try Data(repeating: 2, count: 20).write(to: root.appendingPathComponent("sibling.bin"))
        try FileManager.default.createDirectory(at: root.appendingPathComponent("outside"), withIntermediateDirectories: true)
        try Data(repeating: 3, count: 7).write(to: root.appendingPathComponent("outside/unreported.bin"))
        await delivery.send([PathChange(path: root.appendingPathComponent("a/new.bin").path, isDirectory: false, mustRescan: false)])
        await delivery.send([PathChange(path: root.path, isDirectory: true, mustRescan: true)])
        let queued = await service.pendingQueueObservation(rootPath: subscription.rootPath); XCTAssertEqual(queued?.count, 1)
        gate.signal()
        let current = try await update(subscription) { !$0.isScanning && $0.scope == root.path && $0.snapshot.nodes.first?.logicalBytes == 37 }
        let full = DiskScanner.scan(root)
        XCTAssertEqual(current.snapshot.fileCount, full.fileCount); XCTAssertEqual(current.snapshot.folderCount, full.folderCount)
        XCTAssertEqual(current.snapshot.nodes[0].allocatedBytes, full.nodes[0].allocatedBytes)
        XCTAssertEqual(Dictionary(uniqueKeysWithValues: current.snapshot.nodes.map { ($0.path, $0.logicalBytes) }), Dictionary(uniqueKeysWithValues: full.nodes.map { ($0.path, $0.logicalBytes) }))
        XCTAssertEqual(calls.values, [root.path, root.appendingPathComponent("a").path, root.path])
        XCTAssertEqual(frozen.nodes[0].logicalBytes, 5); XCTAssertEqual(frozen.fileCount, 2)
        await service.unsubscribe(subscription.id, rootPath: subscription.rootPath)
        let final = await service.statistics(); XCTAssertEqual(final.roots, 0); XCTAssertEqual(final.admission.active, 0)
    }
}

private final class RecoveryPaths: @unchecked Sendable {
    private let lock = NSLock(); private var paths: [String] = []
    func append(_ path: String) { lock.withLock { paths.append(path) } }
    var values: [String] { lock.withLock { paths } }
}
private final class RecoveryMonitor: @unchecked Sendable {
    private let lock = NSLock(); private var callback: ScanService.MonitorDelivery?
    func set(_ value: @escaping ScanService.MonitorDelivery) { lock.withLock { callback = value } }
    func send(_ changes: [PathChange]) async { if let value = lock.withLock({ callback }) { await value(changes) } }
}
