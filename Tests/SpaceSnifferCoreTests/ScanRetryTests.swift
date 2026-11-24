import XCTest
import Darwin
@testable import SpaceSnifferCore

final class ScanRetryTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sniffer-retry-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        return root
    }

    func testErrorDecisionTableAndTotalDelayBudget() {
        for code in [EACCES, EPERM, ENOENT, ENOTDIR, ELOOP, EMFILE, ENFILE, ENOMEM, EIO, EINVAL, ENAMETOOLONG, ENOTSUP, Int32.max] {
            for attempt in 1...3 { XCTAssertNil(ScanRetryPolicy.delay(after: code, failedAttempt: attempt)) }
        }
        for code in [EAGAIN, EBUSY, ETIMEDOUT] {
            let delays = (1...3).compactMap { ScanRetryPolicy.delay(after: code, failedAttempt: $0) }
            XCTAssertEqual(delays, [0.01, 0.01])
            XCTAssertEqual(delays.reduce(0, +), 0.02, accuracy: 0.000001)
        }
        XCTAssertEqual(ScanRetryPolicy.delay(after: EINTR, failedAttempt: 1), 0)
        XCTAssertNil(ScanRetryPolicy.delay(after: EINTR, failedAttempt: 3))
        XCTAssertNil(ScanRetryPolicy.delay(after: EAGAIN, failedAttempt: 0))
    }

    func testPermanentErrorsOpenOnceNeverWaitAndPreserveNativeCode() {
        for code in [EACCES, EPERM, ENOENT, ENOTDIR, EMFILE, EIO, Int32.max] {
            var calls = 0, waits = 0, stats = ScanIOStatistics()
            var reader = POSIXDirectoryReader()
            reader.openDirectory = { _ in calls += 1; errno = code; return nil }
            reader.wait = { _, _ in waits += 1; errno = EINVAL; return true }
            XCTAssertThrowsError(try reader.names(at: "/unused", control: .init(), statistics: &stats, progress: {})) {
                XCTAssertEqual(($0 as NSError).domain, NSPOSIXErrorDomain)
                XCTAssertEqual(($0 as NSError).code, Int(code))
            }
            XCTAssertEqual(calls, 1); XCTAssertEqual(waits, 0)
            XCTAssertEqual(stats.openDirectoryCalls, 1); XCTAssertEqual(stats.openRetryDecisions, 0)
        }
    }

    func testTransientFailureThenSuccessKeepsSortAndClosesExactlyOnce() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        for name in ["z", "a", ".hidden"] { try Data([1]).write(to: root.appendingPathComponent(name)) }
        var calls = 0, closes = 0, stats = ScanIOStatistics(), delays: [Double] = []
        var reader = POSIXDirectoryReader()
        reader.openDirectory = { path in
            calls += 1
            if calls == 1 { errno = EBUSY; return nil }
            return opendir(path)
        }
        reader.wait = { _, delay in delays.append(delay); return true }
        reader.closeDirectory = { closes += 1; _ = closedir($0) }
        let names = try reader.names(at: root.path, control: .init(), statistics: &stats, progress: {})
        XCTAssertEqual(names, [".hidden", "a", "z"])
        XCTAssertEqual(calls, 2); XCTAssertEqual(closes, 1); XCTAssertEqual(delays, [0.01])
    }

    func testExhaustionCapsCallsAndPropagatesLastErrorAfterWaitChangesErrno() {
        var calls = 0, stats = ScanIOStatistics(), delays: [Double] = []
        var reader = POSIXDirectoryReader()
        reader.openDirectory = { _ in calls += 1; errno = calls == 3 ? ETIMEDOUT : EAGAIN; return nil }
        reader.wait = { _, delay in delays.append(delay); errno = EPERM; return true }
        XCTAssertThrowsError(try reader.names(at: "/unused", control: .init(), statistics: &stats, progress: {})) {
            XCTAssertEqual(($0 as NSError).code, Int(ETIMEDOUT))
        }
        XCTAssertEqual(calls, 3); XCTAssertEqual(delays, [0.01, 0.01])
        XCTAssertEqual(stats.openRetryDecisions, 2)
        XCTAssertEqual(stats.requestedRetryDelaySeconds, 0.02, accuracy: 0.000001)
    }

    func testInterruptedOpensRetryImmediatelyButStillHaveAttemptCap() {
        var stats = ScanIOStatistics(), delays: [Double] = []
        var reader = POSIXDirectoryReader()
        reader.openDirectory = { _ in errno = EINTR; return nil }
        reader.wait = { _, delay in delays.append(delay); return true }
        XCTAssertThrowsError(try reader.names(at: "/unused", control: .init(), statistics: &stats, progress: {}))
        XCTAssertEqual(stats.openDirectoryCalls, 3); XCTAssertEqual(delays, [0, 0])
    }

    func testMissingNativeDirectoryStopsAfterOneAttempt() throws {
        let root = try fixture()
        try FileManager.default.removeItem(at: root)
        var stats = ScanIOStatistics()
        XCTAssertThrowsError(try POSIXDirectoryReader().names(at: root.path, control: .init(), statistics: &stats, progress: {})) {
            XCTAssertEqual(($0 as NSError).code, Int(ENOENT))
        }
        XCTAssertEqual(stats.openDirectoryCalls, 1)
        XCTAssertEqual(stats.openRetryDecisions, 0)
    }

    func testTransientThenPermanentErrorStopsWithoutSpendingRemainingBudget() {
        var attempts = 0, waits = 0, stats = ScanIOStatistics()
        var reader = POSIXDirectoryReader()
        reader.openDirectory = { _ in attempts += 1; errno = attempts == 1 ? EBUSY : ENOENT; return nil }
        reader.wait = { _, _ in waits += 1; return true }
        XCTAssertThrowsError(try reader.names(at: "/unused", control: .init(), statistics: &stats, progress: {})) {
            XCTAssertEqual(($0 as NSError).code, Int(ENOENT))
        }
        XCTAssertEqual(attempts, 2); XCTAssertEqual(waits, 1)
    }

    func testCancellationDuringRetryDoesNotOpenAgainOrReportAnIssue() throws {
        let control = ScanControl()
        var stats = ScanIOStatistics()
        var reader = POSIXDirectoryReader()
        reader.openDirectory = { _ in errno = EAGAIN; return nil }
        reader.wait = { control, _ in control.cancel(); return false }
        XCTAssertEqual(try reader.names(at: "/unused", control: control, statistics: &stats, progress: {}), [])
        XCTAssertEqual(stats.openDirectoryCalls, 1)
        XCTAssertTrue(control.isCancelled)
        var cancelledStats = ScanIOStatistics()
        XCTAssertEqual(try reader.names(at: "/unused", control: control, statistics: &cancelledStats, progress: {}), [])
        XCTAssertEqual(cancelledStats.openDirectoryCalls, 0)
    }

    func testReadErrorDoesNotReopenAndClosesCursor() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var stats = ScanIOStatistics(), closes = 0
        var reader = POSIXDirectoryReader()
        reader.nextEntry = { _ in errno = EIO; return nil }
        reader.closeDirectory = { closes += 1; _ = closedir($0) }
        XCTAssertThrowsError(try reader.names(at: root.path, control: .init(), statistics: &stats, progress: {})) {
            XCTAssertEqual(($0 as NSError).code, Int(EIO))
        }
        XCTAssertEqual(stats.openDirectoryCalls, 1); XCTAssertEqual(closes, 1)
    }

    func testCancellationClosesAnOpenedCursor() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let control = ScanControl()
        var stats = ScanIOStatistics(), closes = 0
        var reader = POSIXDirectoryReader()
        reader.openDirectory = { path in let cursor = opendir(path); control.cancel(); return cursor }
        reader.closeDirectory = { closes += 1; _ = closedir($0) }
        XCTAssertEqual(try reader.names(at: root.path, control: control, statistics: &stats, progress: {}), [])
        XCTAssertEqual(stats.readDirectoryCalls, 0); XCTAssertEqual(closes, 1)
    }

    func testCancelWakesActualConditionWaitWithoutWaitingForDeadline() {
        let control = ScanControl()
        let entered = DispatchSemaphore(value: 0)
        let finished = expectation(description: "retry unblocked by cancel")
        DispatchQueue.global().async {
            entered.signal()
            XCTAssertFalse(control.waitForRetry(5))
            finished.fulfill()
        }
        XCTAssertEqual(entered.wait(timeout: .now() + 1), .success)
        control.cancel()
        wait(for: [finished], timeout: 1)
        XCTAssertFalse(control.waitForRetry(0))
        XCTAssertTrue(ScanControl().waitForRetry(0))
    }

    func testNativeDeniedDirectoriesStillProduceOneIssueEachAndKeepReadableSibling() throws {
        if getuid() == 0 { throw XCTSkip("root bypasses native permission checks") }
        let root = try fixture(), denied = root.appendingPathComponent("denied")
        try FileManager.default.createDirectory(at: denied, withIntermediateDirectories: true)
        defer { _ = chmod(denied.path, 0o700); try? FileManager.default.removeItem(at: root) }
        try Data([1, 2, 3]).write(to: root.appendingPathComponent("readable"))
        XCTAssertEqual(chmod(denied.path, 0), 0)
        for backend: DiskScanner.MetadataBackend in [.posix, .bulk(.init()), .streaming(.init())] {
            var stats = ScanIOStatistics()
            let result = DiskScanner.scan(root, metadataBackend: backend, diagnostics: { stats = $0 })
            XCTAssertEqual(result.issueCount, 1); XCTAssertEqual(result.issues.count, 1)
            XCTAssertEqual(result.fileCount, 1); XCTAssertEqual(result.folderCount, 2)
            XCTAssertEqual(result.nodes[0].logicalBytes, 3)
            XCTAssertNotNil(result.nodes.first { $0.path == denied.path }?.issue)
            XCTAssertFalse(result.cancelled)
            XCTAssertEqual(stats.openRetryDecisions, 0)
            _ = try result.validated()
        }
    }
}
