import XCTest
@testable import SpaceSnifferAutomation
import SpaceSnifferCore

final class SubtreeQueryTests: XCTestCase, @unchecked Sendable {
    private func fixture(revision: String = "revision-1") -> QueryContext {
        // Node IDs deliberately interleave siblings: subtree order is not array order.
        var snapshot = ScanSnapshot(rootPath: "/r", nodes: [
            DiskNode(id: 0, parent: nil, path: "/r", name: "r", isDirectory: true, children: [1,2]),
            DiskNode(id: 1, parent: 0, path: "/r/large", name: "large", isDirectory: true, children: [3,5]),
            DiskNode(id: 2, parent: 0, path: "/r/focus", name: "focus", isDirectory: true, children: [4,6]),
            DiskNode(id: 3, parent: 1, path: "/r/large/no.bin", name: "no.bin", logicalBytes: 1),
            DiskNode(id: 4, parent: 2, path: "/r/focus/한글.bin", name: "한글.bin", logicalBytes: 2),
            DiskNode(id: 5, parent: 1, path: "/r/large/no.txt", name: "no.txt", logicalBytes: 3),
            DiskNode(id: 6, parent: 2, path: "/r/focus/nest", name: "nest", isDirectory: true, children: [7]),
            DiskNode(id: 7, parent: 6, path: "/r/focus/nest/second.bin", name: "second.bin", logicalBytes: 4)])
        snapshot.tags["/r/focus"] = 4
        return QueryContext(snapshot: snapshot, weights: [10,4,6,1,2,3,4,4], filter: try! ScanFilter(""), mode: .logical, showHidden: true, revision: revision, focus: 0, selection: nil)
    }
    private func paths(_ page: JSONValue) -> [String] {
        guard case .array(let rows) = page.object?["items"] else { return [] }
        return rows.compactMap { $0.object?["path"]?.string }
    }
    func testSubtreePaginationBudgetAndOracleOnInterleavedIDs() throws {
        let context = fixture(); let session = SubtreeQuerySession()
        var args: [String: JSONValue] = ["traversal": .string("subtree"), "path": .string("/r/focus"), "expression": .string("*.bin;:green"), "budget": .int(1), "limit": .int(1)]
        var found: [String] = [], visited = 0, pages = 0
        repeat {
            let page = try session.query(context: context, arguments: args); pages += 1
            XCTAssertLessThanOrEqual(page.object?["traversal_steps"]?.integer ?? 2, 1)
            visited += Int(page.object?["inspected_nodes"]?.integer ?? 0)
            found += paths(page)
            if let next = page.object?["next_cursor"]?.string { args["cursor"] = .string(next) }
            else { XCTAssertEqual(page.object?["complete"], .bool(true)); break }
            XCTAssertLessThan(pages, 30)
        } while true
        let reference = try context.query(command: "query_nodes", arguments: ["path": .string("/r/focus"), "expression": .string("*.bin;:green")])
        XCTAssertEqual(Set(found), Set(paths(reference)))
        XCTAssertEqual(found, ["/r/focus/한글.bin", "/r/focus/nest/second.bin"])
        XCTAssertEqual(visited, 4, "Only the focused subtree is inspected, no root/other branch nodes")
        XCTAssertGreaterThan(pages, visited, "Edge ascent/descent also consumes the bounded traversal budget")
        XCTAssertEqual(session.statistics.cursors, 0); XCTAssertEqual(session.statistics.activePages, 0)
        XCTAssertNil(session.contextLeaseWitness)
    }
    func testCursorIsOneUseAndRejectsChangedScopeExpressionOrRevision() throws {
        let context = fixture(); let session = SubtreeQuerySession()
        let base: [String: JSONValue] = ["traversal": .string("subtree"), "budget": .int(1)]
        let first = try session.query(context: context, arguments: base)
        let cursor = try XCTUnwrap(first.object?["next_cursor"]?.string)
        for change: [String: JSONValue] in [["expression": .string("different")], ["path": .string("/r/focus")], ["offset": .int(1)]] {
            XCTAssertThrowsError(try session.query(context: context, arguments: base.merging(["cursor": .string(cursor)], uniquingKeysWith: { _, b in b }).merging(change, uniquingKeysWith: { _, b in b })))
        }
        XCTAssertThrowsError(try session.query(context: context, arguments: base.merging(["cursor": .string(cursor), "revision": .string("old")], uniquingKeysWith: { _, b in b })))
        let second = try session.query(context: context, arguments: base.merging(["cursor": .string(cursor)], uniquingKeysWith: { _, b in b }))
        XCTAssertEqual(first.object?["evaluated_at"], second.object?["evaluated_at"], "Relative-time filters use one pinned evaluation instant")
        XCTAssertThrowsError(try session.query(context: context, arguments: base.merging(["cursor": .string(cursor)], uniquingKeysWith: { _, b in b }))) { error in
            XCTAssertEqual((error as? ControlError)?.code, "stale_cursor")
        }
        session.reset()
    }
    func testSnapshotOffsetModeAcceptsDefaultsAndKeepsTheOriginalCursorMeaning() throws {
        let context = fixture()
        let page = try context.query(command: "query_nodes", arguments: ["traversal": .string("snapshot"), "cancel_cursor": .bool(false), "offset": .int(4), "budget": .int(2)])
        XCTAssertEqual(page.object?["inspected_nodes"], .int(2)); XCTAssertEqual(page.object?["next_offset"], .int(6))
        XCTAssertEqual(paths(page), ["/r/focus/한글.bin", "/r/large/no.txt"])
    }
    func testLogicalIdleExpiryReleasesContextWhenNextAccessArrives() throws {
        let clock = TestClock(); let context = fixture()
        let session = SubtreeQuerySession(maximumCursors: 2, willRunPage: {}, uptime: { clock.read() })
        let args: [String: JSONValue] = ["traversal": .string("subtree"), "budget": .int(1)]
        let first = try session.query(context: context, arguments: args)
        let oldToken = try XCTUnwrap(first.object?["next_cursor"]?.string)
        clock.advance(59)
        let second = try session.query(context: context, arguments: args.merging(["cursor": .string(oldToken)], uniquingKeysWith: { _, b in b }))
        let nextToken = try XCTUnwrap(second.object?["next_cursor"]?.string)
        weak let lease = session.contextLeaseWitness
        clock.advance(60)
        XCTAssertThrowsError(try session.query(context: context, arguments: args.merging(["cursor": .string(nextToken)], uniquingKeysWith: { _, b in b }))) { error in
            XCTAssertEqual((error as? ControlError)?.code, "stale_cursor")
        }
        XCTAssertNil(lease); XCTAssertEqual(session.statistics.cursors, 0)
    }
    func testBoundedEvictionSharedContextCancellationAndResetRelease() throws {
        let context = fixture(); let session = SubtreeQuerySession(maximumCursors: 2)
        let args: [String: JSONValue] = ["traversal": .string("subtree"), "budget": .int(1)]
        var tokens: [String] = []
        for _ in 0..<3 { tokens.append(try XCTUnwrap(session.query(context: context, arguments: args).object?["next_cursor"]?.string)) }
        XCTAssertEqual(session.statistics.cursors, 2); XCTAssertEqual(session.statistics.evicted, 1)
        XCTAssertEqual(session.statistics.reusedContexts, 2)
        XCTAssertThrowsError(try session.query(context: context, arguments: args.merging(["cursor": .string(tokens[0])], uniquingKeysWith: { _, b in b })))
        let cancelled = try session.query(context: context, arguments: args.merging(["cursor": .string(tokens[1]), "cancel_cursor": .bool(true)], uniquingKeysWith: { _, b in b }))
        XCTAssertEqual(cancelled.object?["cancelled"], .bool(true)); XCTAssertEqual(session.statistics.cursors, 1)
        weak let witness = session.contextLeaseWitness
        XCTAssertNotNil(witness); session.reset(); XCTAssertNil(witness)
        XCTAssertEqual(session.statistics.cursors, 0); XCTAssertEqual(session.statistics.activePages, 0)
    }
    func testDepthLimitFailsWithoutRetainingCursorOrContext() throws {
        let session = SubtreeQuerySession(maximumFramesPerCursor: 2)
        XCTAssertThrowsError(try session.query(context: fixture(), arguments: ["traversal": .string("subtree"), "budget": .int(100)])) { error in
            XCTAssertEqual((error as? ControlError)?.code, "query_limit")
        }
        XCTAssertEqual(session.statistics.cursors, 0); XCTAssertNil(session.contextLeaseWitness)
    }
    func testChangedTableWithSameClaimedRevisionIsRejectedAndOldReaderIsFrozen() throws {
        let old = fixture(); let session = SubtreeQuerySession()
        let first = try session.query(context: old, arguments: ["traversal": .string("subtree"), "budget": .int(1)])
        let token = try XCTUnwrap(first.object?["next_cursor"]?.string)
        var changed = old.snapshot; changed.nodes[4].name = "changed.bin"
        let next = QueryContext(snapshot: changed, weights: old.weights, filter: old.filter, mode: old.mode, showHidden: old.showHidden, revision: old.revision, focus: old.focus, selection: old.selection)
        XCTAssertThrowsError(try session.query(context: next, arguments: ["traversal": .string("subtree"), "cursor": .string(token)])) { error in
            XCTAssertEqual((error as? ControlError)?.code, "stale_revision")
        }
        XCTAssertEqual(old.snapshot.nodes[4].name, "한글.bin"); XCTAssertNil(session.contextLeaseWitness)
    }
    func testDetachedReadActuallyReceivesParentCancellation() async throws {
        let started = DispatchSemaphore(value: 0)
        let parent = Task {
            try await QueryExecution.run {
                started.signal()
                let end = ProcessInfo.processInfo.systemUptime + 3
                while !Task.isCancelled && ProcessInfo.processInfo.systemUptime < end { Thread.sleep(forTimeInterval: 0.001) }
                try Task.checkCancellation()
                return .bool(false)
            }
        }
        let didStart = await Task.detached { Self.waitForStart(started) }.value
        XCTAssertTrue(didStart); parent.cancel()
        do { _ = try await parent.value; XCTFail("Detached query ignored parent cancellation") }
        catch { XCTAssertTrue(error is CancellationError) }
        let (gate, release) = AsyncStream<Void>.makeStream()
        let preCancelled = Task {
            var iterator = gate.makeAsyncIterator(); _ = await iterator.next()
            return try await QueryExecution.run { try self.fixture().query(command: "query_nodes", arguments: ["offset": .int(1), "budget": .int(1)]) }
        }
        preCancelled.cancel(); release.finish()
        do { _ = try await preCancelled.value; XCTFail("A pre-cancelled one-node page must not return results") }
        catch { XCTAssertTrue(error is CancellationError) }
    }
    func testRunningPageKeepsItsSlotAndFrozenLeaseUntilResetCancellationActuallyExits() async throws {
        let started = DispatchSemaphore(value: 0), proceed = DispatchSemaphore(value: 0)
        let session = SubtreeQuerySession(maximumCursors: 1, willRunPage: { started.signal(); Self.wait(proceed) })
        let context = fixture()
        let page = Task.detached { try session.query(context: context, arguments: ["traversal": .string("subtree"), "budget": .int(1)]) }
        let didStart = await Task.detached { Self.waitForStart(started) }.value
        guard didStart else { proceed.signal(); page.cancel(); _ = try? await page.value; return XCTFail("Page did not reach its running boundary") }
        weak let lease = session.contextLeaseWitness
        XCTAssertNotNil(lease); XCTAssertEqual(session.statistics.activePages, 1)
        session.reset()
        XCTAssertEqual(session.statistics.cursors, 0); XCTAssertEqual(session.statistics.activePages, 1)
        XCTAssertNotNil(lease, "The active reader stays frozen until cooperative exit")
        XCTAssertThrowsError(try session.query(context: context, arguments: ["traversal": .string("subtree"), "budget": .int(1)])) { error in
            XCTAssertEqual((error as? ControlError)?.code, "busy", "reset must not admit extra work before the active page exits")
        }
        proceed.signal()
        do { _ = try await page.value; XCTFail("A reset page returned a cursor") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertNil(lease); XCTAssertEqual(session.statistics.activePages, 0)
    }
    func testResetBeforeDetachedCursorCreationRejectsCapturedOwnerEpoch() async throws {
        let session = SubtreeQuerySession(), context = fixture()
        let capturedEpoch = session.epoch
        let (gate, release) = AsyncStream<Void>.makeStream()
        let request = Task.detached {
            var iterator = gate.makeAsyncIterator(); _ = await iterator.next()
            return try session.query(context: context, arguments: ["traversal": .string("subtree"), "budget": .int(1)], epoch: capturedEpoch)
        }
        session.reset(); release.finish()
        do { _ = try await request.value; XCTFail("A delayed old request reopened a reset session") }
        catch { XCTAssertEqual((error as? ControlError)?.code, "stale_revision") }
        XCTAssertEqual(session.statistics.created, 0); XCTAssertEqual(session.statistics.activePages, 0)
        XCTAssertNil(session.contextLeaseWitness)
        _ = try session.query(context: context, arguments: ["traversal": .string("subtree"), "budget": .int(1)], epoch: session.epoch)
        XCTAssertEqual(session.statistics.created, 1)
    }
    func testShutdownBeforeDetachedCreationIsTerminalEvenForNewEpochRequests() async throws {
        let session = SubtreeQuerySession(), context = fixture()
        let epoch = session.epoch
        let (gate, release) = AsyncStream<Void>.makeStream()
        let request = Task.detached {
            var iterator = gate.makeAsyncIterator(); _ = await iterator.next()
            return try session.query(context: context, arguments: ["traversal": .string("subtree")], epoch: epoch)
        }
        session.shutdown(); release.finish()
        do { _ = try await request.value; XCTFail("A delayed request reopened a closed session") }
        catch { XCTAssertEqual((error as? ControlError)?.code, "cancelled") }
        session.reset()
        XCTAssertThrowsError(try session.query(context: context, arguments: ["traversal": .string("subtree")])) { error in
            XCTAssertEqual((error as? ControlError)?.code, "cancelled")
        }
        XCTAssertEqual(session.statistics.created, 0); XCTAssertEqual(session.statistics.activePages, 0)
        XCTAssertNil(session.contextLeaseWitness)
    }
    func testExplicitCancelCanInterruptAnAlreadyRunningContinuationPage() async throws {
        let gate = PageGate(); let context = fixture()
        let session = SubtreeQuerySession(maximumCursors: 1, willRunPage: { gate.enter() })
        let first = try session.query(context: context, arguments: ["traversal": .string("subtree"), "budget": .int(1)])
        let token = try XCTUnwrap(first.object?["next_cursor"]?.string)
        weak let lease = session.contextLeaseWitness
        gate.arm()
        let page = Task.detached { try session.query(context: context, arguments: ["traversal": .string("subtree"), "cursor": .string(token)]) }
        let didStart = await Task.detached { Self.waitForStart(gate.started) }.value
        guard didStart else { gate.proceed.signal(); page.cancel(); _ = try? await page.value; return XCTFail("Continuation did not reach its running boundary") }
        let cancelled = try session.query(context: context, arguments: ["traversal": .string("subtree"), "cursor": .string(token), "cancel_cursor": .bool(true)])
        XCTAssertEqual(cancelled.object?["cancelled"], .bool(true)); XCTAssertEqual(session.statistics.cursors, 0)
        XCTAssertEqual(session.statistics.activePages, 1); XCTAssertNotNil(lease)
        gate.proceed.signal()
        do { _ = try await page.value; XCTFail("Cancelled active cursor returned data") }
        catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertEqual(session.statistics.activePages, 0); XCTAssertNil(lease)
    }
    private final class TestClock: @unchecked Sendable {
        private let lock = NSLock(); private var value: TimeInterval = 0
        func read() -> TimeInterval { lock.lock(); defer { lock.unlock() }; return value }
        func advance(_ delta: TimeInterval) { lock.lock(); defer { lock.unlock() }; value += delta }
    }
    private final class PageGate: @unchecked Sendable {
        private let lock = NSLock(); private var armed = false
        let started = DispatchSemaphore(value: 0), proceed = DispatchSemaphore(value: 0)
        func arm() { lock.lock(); armed = true; lock.unlock() }
        func enter() { lock.lock(); let shouldWait = armed; lock.unlock(); if shouldWait { started.signal(); proceed.wait() } }
    }
    private static func wait(_ gate: DispatchSemaphore) { gate.wait() }
    private static func waitForStart(_ gate: DispatchSemaphore) -> Bool { gate.wait(timeout: .now() + 3) == .success }
}
