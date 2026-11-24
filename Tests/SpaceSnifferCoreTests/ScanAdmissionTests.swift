import XCTest
@testable import SpaceSnifferCore

final class ScanAdmissionTests: XCTestCase, @unchecked Sendable {
    func testQueuedCancellationFIFOAndBoundedCapacityReleasePayload() async throws {
        let admission = ScanAdmission(limit: 1, capacity: 2); defer { admission.shutdown() }
        let gate = DispatchSemaphore(value: 0)
        let started = expectation(description: "first started")
        let finished = expectation(description: "first and last completed"); finished.expectedFulfillmentCount = 2
        let cancelled = expectation(description: "queued completion exactly once"); cancelled.assertForOverFulfill = true
        let released = expectation(description: "queued capture released while first remains blocked")
        let order = AdmissionValues()
        try admission.submit(control: ScanControl(), operation: {
            order.append(1); started.fulfill(); gate.wait(); return ScanSnapshot(rootPath: "/one")
        }, completion: { _ in finished.fulfill() })
        await fulfillment(of: [started], timeout: 3)
        func queued() throws -> UUID {
            let capture = AdmissionCapture { released.fulfill() }
            return try admission.submit(control: ScanControl(), operation: { [capture] in
                _ = capture; XCTFail("cancelled queued work ran"); return ScanSnapshot(rootPath: "/never")
            }, completion: { result in
                if case .cancelledBeforeStart = result {} else { XCTFail("wrong cancellation result") }
                cancelled.fulfill()
            })
        }
        let id = try queued()
        try admission.submit(control: ScanControl(), operation: {
            order.append(3); return ScanSnapshot(rootPath: "/three")
        }, completion: { _ in finished.fulfill() })
        XCTAssertThrowsError(try admission.submit(control: ScanControl(), operation: { ScanSnapshot(rootPath: "/overflow") }, completion: { _ in XCTFail() }))
        admission.cancel(id); admission.cancel(id)
        await fulfillment(of: [cancelled, released], timeout: 3)
        XCTAssertEqual(admission.statistics().active, 1); XCTAssertEqual(admission.statistics().queued, 1)
        gate.signal(); await fulfillment(of: [finished], timeout: 3)
        XCTAssertEqual(order.values(), [1, 3])
        let stats = admission.statistics()
        XCTAssertEqual(stats.peakActive, 1); XCTAssertEqual(stats.finished, 2)
        XCTAssertEqual(stats.cancelledBeforeStart, 1); XCTAssertEqual(stats.rejected, 1)
    }
    func testRunningCancellationKeepsSlotUntilOperationActuallyReturns() async throws {
        let admission = ScanAdmission(limit: 1); defer { admission.shutdown() }
        let gate = DispatchSemaphore(value: 0)
        let started = expectation(description: "running")
        let finished = expectation(description: "both complete"); finished.expectedFulfillmentCount = 2
        let secondRuns = AdmissionValues()
        let id = try admission.submit(control: ScanControl(), operation: {
            started.fulfill(); gate.wait(); return ScanSnapshot(rootPath: "/slow")
        }, completion: { result in
            if case .finished(let snapshot) = result { XCTAssertTrue(snapshot.cancelled) } else { XCTFail() }
            finished.fulfill()
        })
        await fulfillment(of: [started], timeout: 3)
        try admission.submit(control: ScanControl(), operation: {
            secondRuns.append(1); return ScanSnapshot(rootPath: "/next")
        }, completion: { _ in finished.fulfill() })
        admission.cancel(id)
        XCTAssertEqual(admission.statistics().active, 1); XCTAssertEqual(admission.statistics().queued, 1)
        XCTAssertTrue(secondRuns.values().isEmpty)
        gate.signal(); await fulfillment(of: [finished], timeout: 3)
        XCTAssertEqual(secondRuns.values(), [1]); XCTAssertEqual(admission.statistics().peakActive, 1)
    }
    func testShutdownCancelsQueuedOnceAndRejectsNewWork() async throws {
        let admission = ScanAdmission(limit: 1)
        let gate = DispatchSemaphore(value: 0)
        let started = expectation(description: "running")
        let done = expectation(description: "both terminal"); done.expectedFulfillmentCount = 2; done.assertForOverFulfill = true
        try admission.submit(control: ScanControl(), operation: {
            started.fulfill(); gate.wait(); return ScanSnapshot(rootPath: "/running")
        }, completion: { result in
            if case .finished(let s) = result { XCTAssertTrue(s.cancelled) } else { XCTFail() }; done.fulfill()
        })
        await fulfillment(of: [started], timeout: 3)
        try admission.submit(control: ScanControl(), operation: { XCTFail(); return ScanSnapshot(rootPath: "/queued") }, completion: { result in
            if case .cancelledBeforeStart = result {} else { XCTFail() }; done.fulfill()
        })
        admission.shutdown(); admission.shutdown()
        XCTAssertEqual(admission.statistics().active, 1); XCTAssertEqual(admission.statistics().queued, 0)
        XCTAssertThrowsError(try admission.submit(control: ScanControl(), operation: { ScanSnapshot(rootPath: "/rejected") }, completion: { _ in XCTFail() }))
        gate.signal(); await fulfillment(of: [done], timeout: 3)
        XCTAssertEqual(admission.statistics().active, 0)
    }
    func testConcurrentSubmissionCompletesEachJobOnceWithinLimit() async {
        let admission = ScanAdmission(limit: 3, capacity: 1000); defer { admission.shutdown() }
        let done = expectation(description: "1000 terminal callbacks"); done.expectedFulfillmentCount = 1000; done.assertForOverFulfill = true
        let completed = AdmissionValues()
        await withTaskGroup(of: Void.self) { group in
            for index in 0..<1000 {
                group.addTask {
                    do {
                        try admission.submit(control: ScanControl(), operation: {
                            Thread.sleep(forTimeInterval: 0.0001); return ScanSnapshot(rootPath: "/\(index)")
                        }, completion: { _ in completed.append(index); done.fulfill() })
                    } catch { XCTFail("unexpected rejection: \(error)") }
                }
            }
        }
        await fulfillment(of: [done], timeout: 8)
        XCTAssertEqual(Set(completed.values()).count, 1000)
        let stats = admission.statistics()
        XCTAssertEqual(stats.started, 1000); XCTAssertEqual(stats.finished, 1000)
        XCTAssertLessThanOrEqual(stats.peakActive, 3); XCTAssertEqual(stats.active, 0); XCTAssertEqual(stats.queued, 0)
    }
}
private final class AdmissionValues: @unchecked Sendable {
    private let lock = NSLock(); private var storage: [Int] = []
    func append(_ value: Int) { lock.lock(); storage.append(value); lock.unlock() }
    func values() -> [Int] { lock.lock(); defer { lock.unlock() }; return storage }
}
private final class AdmissionCapture: @unchecked Sendable {
    let release: @Sendable () -> Void
    init(_ release: @escaping @Sendable () -> Void) { self.release = release }
    deinit { release() }
}
