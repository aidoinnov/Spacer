import Foundation
import Dispatch
import XCTest
@testable import SpaceSnifferScanEngine

final class LifecycleContractTests: XCTestCase, @unchecked Sendable {
    func testShutdownWaitsForCancelledResultDeliveryWithConcurrentCallers() throws {
        let operationEntered = DispatchSemaphore(value: 0), operationRelease = DispatchSemaphore(value: 0)
        let factoryEntered = expectation(description: "cancelled result factory is gated")
        let factoryRelease = DispatchSemaphore(value: 0), cancellationDone = DispatchSemaphore(value: 0)
        let returned = DispatchSemaphore(value: 0)
        let pool = DirectoryWorkerPool<Int>(workers: 1, capacity: 2, budget: DirectoryIOBudget(limit: 1),
            cancelledOutput: {
                factoryEntered.fulfill()
                _ = factoryRelease.wait(timeout: .now()+8)
                return -1
            })
        defer { operationRelease.signal(); factoryRelease.signal(); pool.shutdown() }
        let first = try XCTUnwrap(pool.submit(control: ScanControl()) {
            operationEntered.signal(); _ = operationRelease.wait(timeout: .now()+8); return 1
        })
        XCTAssertEqual(operationEntered.wait(timeout: .now()+3), .success)
        let cancelled = ScanControl()
        let queued = try XCTUnwrap(pool.submit(control: cancelled) { 2 })
        cancelled.cancel()
        DispatchQueue.global().async { pool.cancelQueued(control: cancelled); cancellationDone.signal() }
        wait(for: [factoryEntered], timeout: 3)
        for _ in 0..<2 { Thread { pool.shutdown(); returned.signal() }.start() }
        operationRelease.signal()
        for _ in 0..<3000 {
            if pool.observation.live == 0 { break }
            Thread.sleep(forTimeInterval: 0.001)
        }
        XCTAssertEqual(pool.observation.live, 0, "native readers have exited")
        XCTAssertFalse(pool.isTerminated, "delivery still owns a terminal-result obligation")
        var earlyReturns = 0
        for _ in 0..<2 {
            if returned.wait(timeout: .now()+0.1) == .success { earlyReturns += 1 }
        }
        XCTAssertEqual(earlyReturns, 0, "shutdown must await cancelled ticket delivery, not just native reader exit")
        factoryRelease.signal()
        XCTAssertEqual(cancellationDone.wait(timeout: .now()+3), .success)
        for _ in earlyReturns..<2 { XCTAssertEqual(returned.wait(timeout: .now()+3), .success) }
        XCTAssertEqual(first.wait(), 1); XCTAssertEqual(queued.wait(), -1)
        XCTAssertTrue(pool.isTerminated)
        XCTAssertNil(pool.submit(control: ScanControl()) { 3 })
    }

    func testWorkerCanRequestShutdownWithoutWaitingOnItsOwnExit() throws {
        let pool = DirectoryWorkerPool<Int>(workers: 1, capacity: 2, budget: DirectoryIOBudget(limit: 1), cancelledOutput: { -1 })
        let entered = DispatchSemaphore(value: 0), release = DispatchSemaphore(value: 0)
        defer { release.signal(); pool.shutdown() }
        let ticket = try XCTUnwrap(pool.submit(control: ScanControl()) {
            entered.signal(); _ = release.wait(timeout: .now()+8)
            pool.requestShutdown(); return 42
        })
        XCTAssertEqual(entered.wait(timeout: .now()+3), .success)
        let alreadyAccepted = try XCTUnwrap(pool.submit(control: ScanControl()) { 7 })
        release.signal()
        XCTAssertEqual(ticket.wait(), 42); XCTAssertEqual(alreadyAccepted.wait(), 7)
        pool.shutdown(); pool.shutdown()
        XCTAssertEqual(pool.observation.live, 0); XCTAssertTrue(pool.isTerminated)
        XCTAssertNil(pool.submit(control: ScanControl()) { 3 })
    }

    func testScopedPermitIsReleasedOnThrowAndSkipsCancelledBody() {
        enum ReadFailure: Error { case expected }
        let budget = DirectoryIOBudget(limit: 1)
        XCTAssertThrowsError(try budget.withPermit(control: ScanControl(), operation: { () throws -> Int in
            XCTAssertEqual(budget.observation.active, 1)
            throw ReadFailure.expected
        }))
        XCTAssertEqual(budget.observation.active, 0)
        let cancelled = ScanControl(); cancelled.cancel()
        let skipped: Int? = budget.withPermit(control: cancelled) { XCTFail("cancelled body ran"); return 0 }
        XCTAssertNil(skipped); XCTAssertEqual(budget.observation.active, 0)
        XCTAssertEqual(budget.withPermit(control: ScanControl()) { 7 }, 7)
        XCTAssertEqual(budget.observation.active, 0)
    }

    func testSuccessfulOptionalNilOutputIsNotCancellation() throws {
        let factory = QualityCounter()
        let pool = DirectoryWorkerPool<Int?>(workers: 1, capacity: 2, budget: DirectoryIOBudget(limit: 1),
            cancelledOutput: { factory.increment(); return -1 })
        defer { pool.shutdown() }
        let successful = try XCTUnwrap(pool.submit(control: ScanControl()) { Optional<Int>.none })
        XCTAssertNil(successful.wait()); XCTAssertEqual(factory.value, 0)
        let cancelled = ScanControl(); cancelled.cancel()
        let skipped = try XCTUnwrap(pool.submit(control: cancelled) { Optional(3) })
        XCTAssertEqual(skipped.wait(), -1); XCTAssertEqual(factory.value, 1)
    }

    func testPlanBudgetStopsBeforeReadingAnExtraLazyElement() {
        var window = DirectoryReadWindow<Int, Int>(futureCapacity: 2)
        let examined = QualityCounter(), submitted = QualityCounter()
        let plans = (0..<10000).lazy.map { value in examined.increment(); return value }
        window.replenish(from: plans, maximumPlans: 0, key: { $0 }, submit: { _ in submitted.increment(); return nil })
        XCTAssertEqual(examined.value, 0); XCTAssertEqual(submitted.value, 0)
        window.replenish(from: plans, maximumPlans: 3, key: { $0 }, submit: { _ in submitted.increment(); return nil })
        XCTAssertEqual(examined.value, 3); XCTAssertEqual(submitted.value, 3)
    }

    func testDuplicatePlansAlsoConsumeInspectionBudget() {
        var window = DirectoryReadWindow<Int, Int>(futureCapacity: 2)
        let examined = QualityCounter(), submitted = QualityCounter()
        let duplicates = (0..<10000).lazy.map { _ in examined.increment(); return 1 }
        window.replenish(from: duplicates, maximumPlans: 3, key: { $0 }, submit: { value in
            submitted.increment(); let ticket = DirectoryReadTicket<Int>(); ticket.finish(value); return ticket
        })
        XCTAssertEqual(examined.value, 3); XCTAssertEqual(submitted.value, 1)
        XCTAssertEqual(window.count, 1)
    }

    func testWindowBoundsLazyPlanInspectionWhenSubmissionFails() {
        var window = DirectoryReadWindow<Int, Int>(futureCapacity: 2)
        let examined = QualityCounter()
        let plans = (0..<10000).lazy.map { value in examined.increment(); return value }
        window.replenish(from: plans, key: { $0 }, submit: { _ in nil })
        XCTAssertEqual(examined.value, 2, "a full OS queue must not trigger an unbounded plan walk")
        XCTAssertTrue(window.isEmpty)
    }
}

private final class QualityCounter: @unchecked Sendable {
    private let lock = NSLock()
    private var stored = 0
    func increment() { lock.lock(); stored += 1; lock.unlock() }
    var value: Int { lock.lock(); defer { lock.unlock() }; return stored }
}
