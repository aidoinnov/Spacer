import XCTest
import Foundation
@testable import SpaceSnifferCore

final class EngineTests: XCTestCase, @unchecked Sendable {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sniffer-engine-" + UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("changed"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("cached"), withIntermediateDirectories: true)
        try Data(repeating: 19, count: 8192).write(to: root.appendingPathComponent("changed/file.bin"))
        try FileManager.default.linkItem(at: root.appendingPathComponent("changed/file.bin"), to: root.appendingPathComponent("cached/link.bin"))
        return root
    }
    private func waitFor(_ subscription: ScanSubscription, predicate: @escaping @Sendable (ScanUpdate) -> Bool = { !$0.isScanning && !$0.snapshot.nodes.isEmpty }) async throws -> ScanUpdate {
        try await withThrowingTaskGroup(of: ScanUpdate.self) { group in
            group.addTask {
                for await update in subscription.updates where predicate(update) { return update }
                throw WaitError.closed
            }
            group.addTask { try await Task.sleep(for: .seconds(8)); throw WaitError.timeout }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
    private enum WaitError: Error { case timeout, closed }

    func testSharedRootCacheReferenceLifecycle() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let service = ScanService()
        let a = await service.subscribe(root, watching: false)
        let b = await service.subscribe(root, watching: false)
        let result = try await waitFor(a)
        XCTAssertEqual(result.snapshot.fileCount, 2)
        let stats = await service.statistics()
        XCTAssertEqual(stats.roots, 1); XCTAssertEqual(stats.subscribers, 2); XCTAssertEqual(stats.scanStarts, 1)
        await service.setTag(9, path: root.path, rootPath: a.rootPath)
        let tagged = try await waitFor(b) { $0.snapshot.tags[root.path] == 9 }
        XCTAssertEqual(tagged.snapshot.tags[root.path], 9)
        await service.unsubscribe(a.id, rootPath: a.rootPath)
        let remaining = await service.statistics(); XCTAssertEqual(remaining.subscribers, 1)
        await service.unsubscribe(b.id, rootPath: b.rootPath)
        let empty = await service.statistics(); XCTAssertEqual(empty.roots, 0)
    }
    func testSameUnderlyingTagAndEmptyClearDoNotAdvanceSnapshotRevision() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let service = ScanService(); let keeper = await service.subscribe(root, watching: false)
        _ = try await waitFor(keeper)
        func revision() async throws -> UInt64 {
            let observer = await service.subscribe(root, watching: false)
            let update = try await waitFor(observer)
            await service.unsubscribe(observer.id, rootPath: observer.rootPath)
            return update.revision
        }
        let initial = try await revision()
        await service.setTag(0, path: root.path, rootPath: keeper.rootPath)
        let noTag = try await revision(); XCTAssertEqual(noTag, initial)
        await service.setTag(9, path: root.path, rootPath: keeper.rootPath)
        let tagged = try await revision(); XCTAssertEqual(tagged, initial + 1)
        await service.setTag(9, path: root.path, rootPath: keeper.rootPath)
        let same = try await revision(); XCTAssertEqual(same, tagged)
        await service.clearTags(scope: root.appendingPathComponent("unused").path, rootPath: keeper.rootPath)
        let unrelated = try await revision(); XCTAssertEqual(unrelated, tagged)
        await service.clearTags(scope: root.path, rootPath: keeper.rootPath)
        let cleared = try await revision(); XCTAssertEqual(cleared, tagged + 1)
        await service.clearTags(scope: root.path, rootPath: keeper.rootPath)
        let empty = try await revision(); XCTAssertEqual(empty, cleared)
        await service.unsubscribe(keeper.id, rootPath: keeper.rootPath)
    }
    func testScopedRefreshKeepsOtherBranchesAndHardLinkAccounting() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let service = ScanService(); let subscription = await service.subscribe(root, watching: false)
        _ = try await waitFor(subscription)
        try Data(repeating: 31, count: 12000).write(to: root.appendingPathComponent("changed/new.txt"))
        await service.rescan(rootPath: subscription.rootPath, scope: root.appendingPathComponent("changed").path)
        let result = try await waitFor(subscription) { !$0.isScanning && $0.snapshot.nodes.contains { $0.name == "new.txt" } }
        let full = DiskScanner.scan(root)
        XCTAssertEqual(result.snapshot.nodes[0].logicalBytes, full.nodes[0].logicalBytes)
        XCTAssertEqual(result.snapshot.nodes[0].allocatedBytes, full.nodes[0].allocatedBytes)
        XCTAssertTrue(result.snapshot.nodes.contains { $0.path.hasSuffix("cached/link.bin") })
        _ = try result.snapshot.validated()
        await service.unsubscribe(subscription.id, rootPath: subscription.rootPath)
    }
    func testCompletedRootIsReusedUntilExplicitRefreshAndEvictedAfterLastSubscriber() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let service = ScanService()
        let a = await service.subscribe(root, watching: false)
        let initial = try await waitFor(a)
        await service.setTag(4, path: root.path, rootPath: a.rootPath)
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("added.bin"))
        let b = await service.subscribe(root.appendingPathComponent("changed/.."), watching: false)
        let reused = try await waitFor(b)
        XCTAssertEqual(reused.snapshot.fileCount, initial.snapshot.fileCount)
        XCTAssertEqual(reused.snapshot.tags[root.path], 4)
        var stats = await service.statistics()
        XCTAssertEqual(stats.scanStarts, 1)
        await service.rescan(rootPath: b.rootPath)
        let refreshed = try await waitFor(b) { !$0.isScanning && $0.snapshot.fileCount == 3 }
        XCTAssertEqual(refreshed.snapshot.tags[root.path], 4)
        await service.unsubscribe(a.id, rootPath: a.rootPath)
        await service.unsubscribe(b.id, rootPath: b.rootPath)
        let c = await service.subscribe(root, watching: false)
        let fresh = try await waitFor(c)
        XCTAssertEqual(fresh.snapshot.fileCount, 3)
        XCTAssertTrue(fresh.snapshot.tags.isEmpty)
        stats = await service.statistics()
        XCTAssertEqual(stats.roots, 1); XCTAssertEqual(stats.scanStarts, 3)
        await service.unsubscribe(c.id, rootPath: c.rootPath)
    }
    func testNestedRootsRemainSeparateAndWatchMembershipIsReferenceCounted() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let service = ScanService()
        let a = await service.subscribe(root, watching: true)
        _ = try await waitFor(a)
        let b = await service.subscribe(root, watching: true)
        _ = try await waitFor(b)
        await service.setWatching(false, subscription: a)
        let stillWatching = try await waitFor(a) { $0.watchActive }
        XCTAssertTrue(stillWatching.watchActive)
        await service.unsubscribe(b.id, rootPath: b.rootPath)
        _ = try await waitFor(a) { !$0.watchActive }
        let child = await service.subscribe(root.appendingPathComponent("changed"), watching: false)
        let nested = try await waitFor(child)
        XCTAssertEqual(nested.snapshot.fileCount, 1)
        let stats = await service.statistics()
        XCTAssertEqual(stats.roots, 2); XCTAssertEqual(stats.scanStarts, 2)
        await service.setWatching(true, subscription: a)
        _ = try await waitFor(a) { $0.watchActive }
        await service.unsubscribe(a.id, rootPath: a.rootPath)
        await service.unsubscribe(child.id, rootPath: child.rootPath)
        let empty = await service.statistics()
        XCTAssertEqual(empty.roots, 0)
    }
    func testFSEventsBurstAndWatchReplacementPreserveIndependentBranches() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        for i in 0..<32 {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("burst-\(i)"), withIntermediateDirectories: true)
        }
        let service = ScanService(); let subscription = await service.subscribe(root, watching: true)
        _ = try await waitFor(subscription)
        for i in 0..<32 {
            try Data(repeating: UInt8(i), count: i + 1).write(to: root.appendingPathComponent("burst-\(i)/event.bin"))
        }
        let burst = try await waitFor(subscription) { !$0.isScanning && $0.snapshot.fileCount == 34 }
        let full = DiskScanner.scan(root)
        XCTAssertEqual(burst.snapshot.nodes[0].logicalBytes, full.nodes[0].logicalBytes)
        XCTAssertEqual(burst.snapshot.nodes[0].allocatedBytes, full.nodes[0].allocatedBytes)
        XCTAssertTrue(burst.snapshot.nodes.contains { $0.path.hasSuffix("cached/link.bin") })
        // Invalidate the old monitor and clear its pending work, then require new content
        // from the replacement monitor rather than accepting an old idle update.
        await service.setWatching(false, subscription: subscription)
        await service.stop(rootPath: subscription.rootPath)
        await service.setWatching(true, subscription: subscription)
        try Data([2, 4, 6]).write(to: root.appendingPathComponent("burst-31/replacement.bin"))
        let replacement = try await waitFor(subscription) {
            !$0.isScanning && $0.watchActive && $0.snapshot.nodes.contains { $0.name == "replacement.bin" }
        }
        XCTAssertEqual(replacement.snapshot.fileCount, 35)
        _ = try replacement.snapshot.validated()
        await service.unsubscribe(subscription.id, rootPath: subscription.rootPath)
        let empty = await service.statistics(); XCTAssertEqual(empty.roots, 0)
    }
    func testFSEventsWorkerDetectsFileCreation() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let service = ScanService(); let subscription = await service.subscribe(root, watching: true)
        let initial = try await waitFor(subscription) {!$0.isScanning && $0.watchActive}
        XCTAssertTrue(initial.watchActive)
        try Data(repeating: 41, count: 2048).write(to: root.appendingPathComponent("changed/watch-added.txt"))
        let result = try await waitFor(subscription) { !$0.isScanning && $0.snapshot.nodes.contains { $0.name == "watch-added.txt" } }
        XCTAssertEqual(result.snapshot.fileCount, 3)
        await service.unsubscribe(subscription.id, rootPath: subscription.rootPath)
    }
    func testLatestWorkerHasOnePendingJobAndRunsOffMainThread() async {
        let worker = LatestWorker<Int>(); defer { worker.shutdown() }
        let gate = DispatchSemaphore(value: 0)
        let started = expectation(description: "worker started")
        let finished = expectation(description: "latest job completed")
        let values = LockedValues()
        worker.submit(operation: { _ in started.fulfill(); gate.wait(); return 0 }, completion: { values.append($0) })
        await fulfillment(of: [started], timeout: 3)
        for index in 1...1000 {
            worker.submit(operation: { _ in
                XCTAssertFalse(Thread.isMainThread); return index
            }, completion: { value in
                values.append(value); if value == 1000 { finished.fulfill() }
            })
        }
        gate.signal()
        await fulfillment(of: [finished], timeout: 3)
        XCTAssertEqual(values.read(), [1000])
    }
    func testParentTagMaskAccumulatesInsteadOfOverriding() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var snapshot = DiskScanner.scan(root)
        let file = try XCTUnwrap(snapshot.nodes.first { $0.name == "file.bin" })
        snapshot.tags[snapshot.rootPath] = 1 // red
        snapshot.tags[root.appendingPathComponent("changed").path] = 4 // green
        XCTAssertTrue(try ScanFilter(":red").matches(file, snapshot: snapshot))
        XCTAssertTrue(try ScanFilter(":green").matches(file, snapshot: snapshot))
        XCTAssertFalse(try ScanFilter(":blue").matches(file, snapshot: snapshot))
    }
    @MainActor func testArtifactActorRoundtripFromMainActor() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let snapshot = DiskScanner.scan(root)
        let url = root.appendingPathComponent("snapshot.sns")
        try await ArtifactWorker.shared.save(snapshot, to: url)
        let loaded = try await ArtifactWorker.shared.load(url)
        XCTAssertEqual(loaded.nodes[0].logicalBytes, snapshot.nodes[0].logicalBytes)
        let samples = WorkerTelemetry.shared.snapshot()
        XCTAssertEqual(samples["snapshot.load"]?.mainThreadRuns, 0)
        XCTAssertEqual(samples["snapshot.save"]?.mainThreadRuns, 0)
    }
}
private final class LockedValues: @unchecked Sendable {
    private let lock = NSLock(); private var values: [Int] = []
    func append(_ value: Int) { lock.lock(); values.append(value); lock.unlock() }
    func read() -> [Int] { lock.lock(); defer { lock.unlock() }; return values }
}
