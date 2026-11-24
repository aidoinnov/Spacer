import Foundation
import Dispatch
import XCTest
@testable import SpaceSnifferScanEngine

final class SharedEngineTests: XCTestCase {
    struct WindowsFixtureMetadata: Sendable, Equatable {
        let volume: UInt64
        let fileIDHigh: UInt64
        let fileIDLow: UInt64
    }
    struct FixtureReader: DirectoryBatchReader {
        let entry: DirectoryEntry<WindowsFixtureMetadata>
        func readDirectory(at path: String, control: ScanControl) -> DirectoryListing<WindowsFixtureMetadata> {
            DirectoryListing(names: [entry.name], entries: control.isCancelled ? [] : [entry])
        }
    }
    func testFolderContractDoesNotTruncateWindowsIdentityOrNormalizeNames() throws {
        let identity = WindowsFixtureMetadata(volume: .max, fileIDHigh: .max, fileIDLow: 42)
        let entry = DirectoryEntry(name: "cafe\u{301}-한글", values: identity, directoryEntryCount: nil)
        let budget = DirectoryIOBudget(limit: 1)
        let pool = DirectoryWorkerPool<DirectoryListing<WindowsFixtureMetadata>>(
            workers: 1, capacity: 2, budget: budget,
            cancelledOutput: { DirectoryListing(names: [], entries: []) })
        defer { pool.shutdown() }
        let ticket = try XCTUnwrap(pool.submit(reader: FixtureReader(entry: entry), path: "C:\\fixture", control: ScanControl()))
        let batch = ticket.wait()
        XCTAssertEqual(batch.entries?.first?.values, identity)
        XCTAssertEqual(Array(batch.names[0].utf8), Array(entry.name.utf8))
        XCTAssertEqual(budget.observation.active, 0)
    }
    func testCompletedResultsStayChargedUntilConsumptionAndRefill() throws {
        var window = DirectoryReadWindow<Int, Int>(futureCapacity: 2)
        let count = Counter()
        func submit(_ value: Int) -> DirectoryReadTicket<Int> {
            count.increment(); let ticket = DirectoryReadTicket<Int>(); ticket.finish(value); return ticket
        }
        window.replenish(from: [1, 2, 3], key: { $0 }, submit: submit)
        XCTAssertEqual(window.count, 2); XCTAssertEqual(count.value, 2)
        window.replenish(from: [3, 4], key: { $0 }, submit: submit)
        XCTAssertEqual(count.value, 2, "completed results still occupy capacity")
        let current = try XCTUnwrap(window.take(for: 1))
        window.replenish(from: [2, 3, 4], key: { $0 }, submit: submit)
        XCTAssertEqual(window.count, 2); XCTAssertEqual(count.value, 3)
        XCTAssertEqual(current.wait(), 1); XCTAssertEqual(window.take(for: 3)?.wait(), 3)
    }
    func testDisabledWindowAndDuplicatePlansCannotOverproduce() {
        var disabled = DirectoryReadWindow<Int, Int>(futureCapacity: 0)
        disabled.replenish(from: [1], key: { $0 }, submit: { _ in XCTFail("disabled producer ran"); return nil })
        var window = DirectoryReadWindow<Int, Int>(futureCapacity: 2)
        let count = Counter()
        window.replenish(from: [1, 1, 2, 3], maximumPlans: 4, key: { $0 }, submit: { value in
            count.increment(); let ticket = DirectoryReadTicket<Int>(); ticket.finish(value); return ticket
        })
        XCTAssertEqual(count.value, 2); XCTAssertEqual(window.count, 2)
        window.removeAll(); XCTAssertTrue(window.isEmpty)
    }
    func testPlatformThresholdsAreInputsToSharedWindowPolicy() {
        let mac = DirectoryReadWindowPolicy(concurrency: 2, minimumSiblingCount: 64, admittedEntryRange: 64...1024)
        let alternate = DirectoryReadWindowPolicy(concurrency: 2, minimumSiblingCount: 8, admittedEntryRange: 8...4096, admitUnknownEntryCount: true)
        XCTAssertFalse(mac.admits(entryCount: 20)); XCTAssertTrue(alternate.admits(entryCount: 20))
        XCTAssertFalse(mac.admits(entryCount: nil)); XCTAssertTrue(alternate.admits(entryCount: nil))
        XCTAssertTrue(mac.hasVacancy(outstanding: 0, pending: 2))
        XCTAssertFalse(mac.hasVacancy(outstanding: 1, pending: 2))
        XCTAssertFalse(mac.hasVacancy(outstanding: 0, pending: 1))
        XCTAssertEqual(alternate.minimumSiblingCount, 8)
    }
    func testQueuedCancellationIsScopedAndQueueRemainsBounded() throws {
        let budget = DirectoryIOBudget(limit: 1)
        let pool = DirectoryWorkerPool<Int>(workers: 1, capacity: 1, budget: budget, cancelledOutput: { -1 })
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        defer { release.signal(); pool.shutdown() }
        let firstControl = ScanControl(), queuedControl = ScanControl()
        let first = try XCTUnwrap(pool.submit(control: firstControl) {
            entered.signal(); _ = release.wait(timeout: .now()+5); return 1
        })
        XCTAssertEqual(entered.wait(timeout: .now()+3), .success)
        let queued = try XCTUnwrap(pool.submit(control: queuedControl) { 2 })
        XCTAssertNil(pool.submit(control: ScanControl()) { 3 })
        queuedControl.cancel(); pool.cancelQueued(control: queuedControl)
        XCTAssertEqual(queued.wait(), -1); XCTAssertFalse(firstControl.isCancelled)
        release.signal(); XCTAssertEqual(first.wait(), 1)
        XCTAssertEqual(budget.observation.active, 0)
    }
    func testCancelledPermitDoesNotRunOSOperation() throws {
        let control = ScanControl(); control.cancel()
        let pool = DirectoryWorkerPool<Int>(workers: 1, capacity: 1, budget: DirectoryIOBudget(limit: 1), cancelledOutput: { -1 })
        defer { pool.shutdown() }
        let ticket = try XCTUnwrap(pool.submit(control: control) { XCTFail("cancelled OS operation ran"); return 1 })
        XCTAssertEqual(ticket.wait(), -1)
    }
    func testPlatformThreadConfigurationIsInjectedOncePerWorker() throws {
        let count = Counter()
        let pool = DirectoryWorkerPool<Int>(workers: 1, capacity: 2, budget: DirectoryIOBudget(limit: 1), cancelledOutput: { -1 },
            configureWorker: { _, _ in count.increment() })
        defer { pool.shutdown() }
        for value in 1...3 {
            let ticket = try XCTUnwrap(pool.submit(control: ScanControl()) { value })
            XCTAssertEqual(ticket.wait(), value)
        }
        XCTAssertEqual(count.value, 1)
    }
    func testObservedBytesDrainExactlyOnceBetweenParents() throws {
        var batch = ObservedByteBatch()
        batch.add(parent: 2, logical: 5, allocated: 4096)
        batch.add(parent: 2, logical: 7, allocated: 8192)
        let delta = try XCTUnwrap(batch.drain())
        XCTAssertEqual(delta.parent, 2); XCTAssertEqual(delta.logical, 12); XCTAssertEqual(delta.allocated, 12288)
        XCTAssertNil(batch.drain())
        batch.add(parent: 3, logical: 1, allocated: 0)
        XCTAssertEqual(batch.drain()?.parent, 3)
    }
    func testPublicationGrowthIsSharedAcrossPlatforms() {
        var policy = ScanPublication()
        XCTAssertFalse(policy.shouldPublish(nodeCount: 0))
        XCTAssertTrue(policy.shouldPublish(nodeCount: 1))
        XCTAssertTrue(policy.shouldPublish(nodeCount: 2))
        XCTAssertFalse(policy.shouldPublish(nodeCount: 3))
        XCTAssertTrue(policy.shouldPublish(nodeCount: 4))
    }
    func testNativeFailureDomainAndCodeAreNotReinterpreted() {
        let output = DirectoryReadOutput<Int, Int>(value: .failure(domain: "Win32", code: 5), statistics: 0)
        guard case let .failure(domain, code) = output.value else { return XCTFail("wrong result") }
        XCTAssertEqual(domain, "Win32"); XCTAssertEqual(code, 5)
    }
    func testCancellationSkipsRetryWait() {
        let control = ScanControl(); control.cancel()
        XCTAssertFalse(control.waitForRetry(10))
    }
}
private final class Counter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    func increment() { lock.lock(); stored += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return stored }
}
