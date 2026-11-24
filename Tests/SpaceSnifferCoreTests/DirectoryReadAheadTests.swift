import XCTest
import Darwin
@testable import SpaceSnifferCore

final class DirectoryReadAheadTests: XCTestCase, @unchecked Sendable {
    func testSharedEntryHasThePriorInlineMetadataLayout() {
        struct PriorEntryShape {
            let name: String
            let values: NativeFileMetadata?
            let directoryEntryCount: UInt32?
        }
        XCTAssertEqual(MemoryLayout<NativeDirectoryMetadata.Entry>.size, MemoryLayout<PriorEntryShape>.size)
        XCTAssertEqual(MemoryLayout<NativeDirectoryMetadata.Entry>.stride, MemoryLayout<PriorEntryShape>.stride)
        XCTAssertEqual(MemoryLayout<NativeDirectoryMetadata.Entry>.alignment, MemoryLayout<PriorEntryShape>.alignment)
    }
    func testSiblingAdmissionBoundsBothWorkerLimitsToUsefulFrontiers() throws {
        for branches in [32, 64] { for files in [1, 20, 96] {
            let root = try fixture(branches: branches, files: files)
            defer { try? FileManager.default.removeItem(at: root) }
            let calls = ReadAheadCounter()
            let reader = NativeDirectoryMetadata(maximumEntries: 131_072, maximumEstimatedBytes: 32*1024*1024, minimumEntries: 16,
                countCall: { path, attrs, buffer, size, flags in
                    calls.increment(); return getattrlist(path, &attrs, buffer, size, flags)
                })
            for concurrency in [2, 4] {
                calls.set(0); var statistics = ScanIOStatistics()
                let result = DiskScanner.scan(root, metadataBackend: .ordered(reader), directoryConcurrency: concurrency, diagnostics: { statistics = $0 })
                XCTAssertEqual(result.fileCount, branches*files)
                XCTAssertEqual(calls.value, branches < 64 ? 0 : files < 64 ? MacScanResources.admissionProbeLimit : 1)
                if branches < 64 || files < 64 { XCTAssertEqual(statistics.prefetchScheduled, 0) }
                else { XCTAssertGreaterThan(statistics.prefetchUsed, 0) }
            }
        } }
    }
    private func fixture(branches: Int = 64, files: Int = 96) throws -> URL {
        let root = URL(fileURLWithPath: "/private/tmp/read-ahead-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for branch in 0..<branches {
            let directory = root.appendingPathComponent("b\(branch)")
            try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
            for index in 0..<files { try Data(repeating: UInt8(index % 255), count: index % 33).write(to: directory.appendingPathComponent("f\(index)")) }
        }
        return root.standardizedFileURL
    }
    private func resetTimes(_ root: URL) throws {
        let iterator = try XCTUnwrap(FileManager.default.enumerator(at: root, includingPropertiesForKeys: nil))
        let paths = [root] + iterator.compactMap { $0 as? URL }
        for path in paths {
            var dates = [timespec(tv_sec: 1_700_000_000, tv_nsec: 0), timespec(tv_sec: 1_700_000_000, tv_nsec: 0)]
            XCTAssertEqual(dates.withUnsafeMutableBufferPointer { utimensat(AT_FDCWD, path.path, $0.baseAddress!, AT_SYMLINK_NOFOLLOW) }, 0)
        }
    }
    private static func nativePath(_ fd: Int32) -> String {
        var bytes = [CChar](repeating: 0, count: Int(PATH_MAX))
        let status = bytes.withUnsafeMutableBufferPointer { fcntl(fd, F_GETPATH, UnsafeMutableRawPointer($0.baseAddress!)) }
        return status == 0 ? String(decoding: bytes.prefix { $0 != 0 }.map { UInt8(bitPattern: $0) }, as: UTF8.self) : ""
    }
    func testTwoAndFourPreserveExactNodesIDsFieldsAndExports() throws {
        let root = try fixture(branches: 64); defer { try? FileManager.default.removeItem(at: root) }
        try Data([1,2]).write(to: root.appendingPathComponent("한글-😀-cafe\u{301}"))
        try FileManager.default.linkItem(at: root.appendingPathComponent("b0/f1"), to: root.appendingPathComponent(".hardlink"))
        try FileManager.default.createSymbolicLink(atPath: root.appendingPathComponent("cycle").path, withDestinationPath: ".")
        try resetTimes(root)
        var serial = DiskScanner.scan(root, metadataBackend: .automatic(.orderedScan), directoryConcurrency: 1)
        for concurrency in [2,4] {
            try resetTimes(root); var statistics = ScanIOStatistics()
            var result = DiskScanner.scan(root, metadataBackend: .automatic(.orderedScan), directoryConcurrency: concurrency, diagnostics: { statistics = $0 })
            XCTAssertGreaterThan(statistics.prefetchScheduled, 0); XCTAssertGreaterThan(statistics.prefetchUsed, 0)
            XCTAssertEqual(Array(result.nodes), Array(serial.nodes)); XCTAssertEqual(result.fileCount, serial.fileCount)
            XCTAssertEqual(result.folderCount, serial.folderCount); XCTAssertEqual(result.issues, serial.issues)
            XCTAssertEqual(result.volumeCoverage, serial.volumeCoverage); _ = try result.validated()
            XCTAssertEqual(Report.simpleFileList(result, ids: Set(result.nodes.indices), weights: result.nodes.map(\.allocatedBytes)),
                           Report.simpleFileList(serial, ids: Set(serial.nodes.indices), weights: serial.nodes.map(\.allocatedBytes)))
            serial.volumeFree = 0; result.volumeFree = 0
            XCTAssertEqual(try SNSSnapshot.encode(result), try SNSSnapshot.encode(serial))
        }
        XCTAssertEqual(MacScanResources.directoryIO.observation.active, 0)
    }
    func testRollingWindowRefillsBeforeWaitingForCurrentTicket() throws {
        let root = try fixture(branches: 64)
        defer { try? FileManager.default.removeItem(at: root) }
        try resetTimes(root)
        let serial = DiskScanner.scan(root, metadataBackend: .ordered(.orderedScan))
        try resetTimes(root)
        let blocked = ReadAheadCounter(), replacement = ReadAheadCounter(), timedOut = ReadAheadCounter()
        let release = DispatchSemaphore(value: 0)
        let native = NativeDirectoryMetadata(maximumEntries: 131_072, maximumEstimatedBytes: 32*1024*1024, minimumEntries: 16,
            call: { fd, attrs, buffer, size, flags in
                let path = Self.nativePath(fd)
                // DFS starts b9 inline, then accepts the b8 ticket. Its
                // replacement b7 must be submitted before waiting for b8.
                if path.hasSuffix("/b8"), blocked.next() == 1 {
                    if release.wait(timeout: .now()+3) == .timedOut { timedOut.increment() }
                }
                let count = getattrlistbulk(fd, &attrs, buffer, size, flags)
                if path.hasSuffix("/b7"), count > 0 { replacement.increment(); release.signal() }
                return count
            })
        let result = DiskScanner.scan(root, metadataBackend: .ordered(native), directoryConcurrency: 2)
        XCTAssertGreaterThan(blocked.value, 0)
        XCTAssertGreaterThan(replacement.value, 0)
        XCTAssertEqual(timedOut.value, 0, "rolling replacement must run before builder wait completes")
        XCTAssertEqual(Array(result.nodes), Array(serial.nodes))
        XCTAssertEqual(MacScanResources.directoryIO.observation.active, 0)
    }

    func testBoundedNameOverflowClosesCursorAndRequestsInlineRetry() throws {
        let root = try fixture(branches: 1, files: 2200); defer { try? FileManager.default.removeItem(at: root) }
        let result = OrderedDirectoryReader.prefetch(root.appendingPathComponent("b0").path, control: ScanControl())
        guard case .retryInline = result.value else { return XCTFail("wide speculative listing must retry inline") }
        XCTAssertEqual(result.statistics.openDirectoryCalls, 1)
        XCTAssertGreaterThan(result.statistics.bulkCalls, 0)
        XCTAssertLessThan(result.statistics.bulkReturnedRecords, 2600, "speculation must stop at its bounded native prefix")
        var descriptor: Int32 = -1
        let reader = POSIXDirectoryReader(openDirectory: { path in
            let directory = opendir(path); if let directory { descriptor = dirfd(directory) }; return directory
        })
        var statistics = ScanIOStatistics()
        XCTAssertThrowsError(try reader.names(at: root.path, control: ScanControl(), statistics: &statistics, budget: (1,1), progress: {}))
        XCTAssertGreaterThanOrEqual(descriptor, 0); XCTAssertEqual(fcntl(descriptor, F_GETFD), -1); XCTAssertEqual(errno, EBADF)
    }
    func testWorkerNameCancellationChecksWithinSixtyFourRecords() throws {
        let root = try fixture(branches: 1, files: 200); defer { try? FileManager.default.removeItem(at: root) }
        let control = ScanControl(); var reads = 0
        let reader = POSIXDirectoryReader(nextEntry: { directory in
            reads += 1
            let entry = readdir(directory)
            if reads == 10 { control.cancel() }
            return entry
        })
        var statistics = ScanIOStatistics()
        _ = try reader.names(at: root.appendingPathComponent("b0").path, control: control, statistics: &statistics, polling: .batch64, progress: {})
        XCTAssertGreaterThanOrEqual(reads, 10); XCTAssertLessThanOrEqual(reads - 10, 63)
        XCTAssertTrue(control.isCancelled)
    }
    func testUnsupportedBulkReusesFirstNamesAndNativeOpenErrorIsExplicit() throws {
        let root = try fixture(branches: 1, files: 100); defer { try? FileManager.default.removeItem(at: root) }
        let native = NativeDirectoryMetadata(call: { _,_,_,_,_ in errno = ENOTSUP; return -1 })
        let result = OrderedDirectoryReader.prefetch(root.appendingPathComponent("b0").path, control: ScanControl(), native: native)
        guard case .listing(let listing) = result.value else { return XCTFail("must preserve names for fallback") }
        XCTAssertEqual(listing.names.count, 100); XCTAssertNil(listing.entries)
        XCTAssertEqual(result.statistics.openDirectoryCalls, 1); XCTAssertEqual(result.statistics.bulkCalls, 1)
        let missing = OrderedDirectoryReader.prefetch(root.appendingPathComponent("absent").path, control: ScanControl())
        guard case .failure(let domain, let code) = missing.value else { return XCTFail("missing directory must report open failure") }
        XCTAssertEqual(domain, NSPOSIXErrorDomain); XCTAssertEqual(code, Int(ENOENT))
    }
    func testPoolCapacityCancellationAndPermitsAreIndependentFromScanAdmission() async throws {
        let budget = DirectoryIOBudget(limit: 1); let pool = DirectoryReadPool(workers: 1, capacity: 1, budget: budget)
        defer { pool.shutdown() }
        let gate = DispatchSemaphore(value: 0); defer { gate.signal() }
        let started = expectation(description: "reader holds its permit")
        let first = try XCTUnwrap(pool.submit(control: ScanControl(), operation: {
            started.fulfill(); _ = gate.wait(timeout: .now()+8)
            return DirectoryReadOutput(value: .retryInline, statistics: ScanIOStatistics())
        }))
        await fulfillment(of: [started], timeout: 3)
        XCTAssertEqual(budget.observation.active, 1)
        let cancelled = ScanControl(); let calls = ReadAheadCounter()
        let second = try XCTUnwrap(pool.submit(control: cancelled, operation: {
            calls.increment(); return DirectoryReadOutput(value: .retryInline, statistics: ScanIOStatistics())
        }))
        XCTAssertNil(pool.submit(control: ScanControl(), operation: { DirectoryReadOutput(value: .retryInline, statistics: ScanIOStatistics()) }))
        cancelled.cancel(); pool.cancelQueued(control: cancelled)
        guard case .cancelled = second.wait().value else { return XCTFail("cancelled queued work must not run") }
        XCTAssertEqual(calls.value, 0); XCTAssertEqual(budget.observation.active, 1) // unrelated first reader is still gated
        gate.signal(); _ = first.wait(); XCTAssertEqual(budget.observation.active, 0)
        pool.shutdown(); XCTAssertEqual(pool.observation.live, 0); XCTAssertEqual(pool.observation.queued, 0)
    }
    func testActiveReaderCancellationClosesNativeFDAheadOfTicketCompletion() async throws {
        let root = try fixture(branches: 1, files: 100); defer { try? FileManager.default.removeItem(at: root) }
        let budget = DirectoryIOBudget(limit: 1); let pool = DirectoryReadPool(workers: 1, capacity: 2, budget: budget)
        defer { pool.shutdown() }
        let gate = DispatchSemaphore(value: 0); defer { gate.signal() }
        let entered = expectation(description: "private metadata FD open"); let control = ScanControl(); let descriptor = ReadAheadCounter()
        let native = NativeDirectoryMetadata(call: { fd,_,_,_,_ in
            descriptor.set(Int(fd)); entered.fulfill(); _ = gate.wait(timeout: .now()+8); return 0
        })
        let path = root.appendingPathComponent("b0").path
        let ticket = try XCTUnwrap(pool.submit(control: control, operation: { OrderedDirectoryReader.prefetch(path, control: control, native: native) }))
        await fulfillment(of: [entered], timeout: 3); control.cancel(); gate.signal()
        guard case .cancelled = ticket.wait().value else { return XCTFail("cancelled read must deliver no usable batch") }
        XCTAssertEqual(fcntl(Int32(descriptor.value), F_GETFD), -1); XCTAssertEqual(errno, EBADF)
        XCTAssertEqual(budget.observation.active, 0)
    }
    func testEightMastersAndReadAheadFinishWithoutPermitDeadlock() async throws {
        // Reproduce permit saturation deterministically, rather than treating
        // 49k files finishing within12s under TSAN as a deadlock criterion.
        let root = try fixture(branches: 64, files: 1); defer { try? FileManager.default.removeItem(at: root) }
        let admission = ScanAdmission(limit: 8); defer { admission.shutdown() }
        let rootsEntered = expectation(description: "eight root reads hold all permits")
        let childrenEntered = expectation(description: "eight inline children hold all permits with futures queued")
        rootsEntered.expectedFulfillmentCount = 8; childrenEntered.expectedFulfillmentCount = 8
        let rootGate = DispatchSemaphore(value: 0), childGate = DispatchSemaphore(value: 0)
        defer { for _ in 0..<8 { rootGate.signal(); childGate.signal() } }
        let completed = expectation(description: "all eight builders finish"); completed.expectedFulfillmentCount = 8
        let failures = ReadAheadCounter(), timedOut = ReadAheadCounter(); let rootName = root.lastPathComponent
        let native = NativeDirectoryMetadata(minimumEntries: 0,
            countCall: { path, attrs, buffer, bytes, flags in
                let status = getattrlist(path, &attrs, buffer, bytes, flags)
                // Stale-but-eligible hints activate actual workers for a tiny
                // fixture. Hints must never replace observed file coverage.
                if status == 0 { buffer.storeBytes(of: UInt32(64), toByteOffset: 24, as: UInt32.self) }
                return status
            }, call: { fd, attrs, buffer, bytes, flags in
                let count = getattrlistbulk(fd, &attrs, buffer, bytes, flags)
                if count > 0 {
                    let path = Self.nativePath(fd)
                    if path.hasSuffix("/"+rootName) {
                        rootsEntered.fulfill()
                        if rootGate.wait(timeout: .now()+8) == .timedOut { timedOut.increment() }
                    } else if path.hasSuffix("/b9") {
                        childrenEntered.fulfill()
                        if childGate.wait(timeout: .now()+8) == .timedOut { timedOut.increment() }
                    }
                }
                return count
            })
        for _ in 0..<8 {
            try admission.submit(control: ScanControl(), operation: {
                var io = ScanIOStatistics()
                let result = DiskScanner.scan(root, metadataBackend: .ordered(native), directoryConcurrency: 4, diagnostics: { io = $0 })
                if result.fileCount != 64 || result.issueCount != 0 || result.cancelled || io.prefetchUsed == 0 { failures.increment() }
                return result
            }, completion: { _ in completed.fulfill() })
        }
        await fulfillment(of: [rootsEntered], timeout: 6)
        XCTAssertEqual(MacScanResources.directoryIO.observation.active, 8)
        for _ in 0..<8 { rootGate.signal() }
        await fulfillment(of: [childrenEntered], timeout: 6)
        XCTAssertEqual(MacScanResources.directoryIO.observation.active, 8)
        for _ in 0..<8 { childGate.signal() }
        await fulfillment(of: [completed], timeout: 8)
        XCTAssertEqual(timedOut.value, 0); XCTAssertEqual(failures.value, 0)
        XCTAssertLessThanOrEqual(MacScanResources.directoryIO.observation.peak, 8)
        XCTAssertEqual(MacScanResources.directoryIO.observation.active, 0)
    }

    func testLaterDirectoryCanReadFirstWithoutChangingBuilderOrder() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        try resetTimes(root)
        let original = DiskScanner.scan(root, metadataBackend: .ordered(.orderedScan))
        try resetTimes(root)
        let delay = ReadAheadCounter(), laterFinished = ReadAheadCounter()
        let releaseFirst = DispatchSemaphore(value: 0); defer { releaseFirst.signal() }
        let native = NativeDirectoryMetadata(maximumEntries: 131_072, maximumEstimatedBytes: 32*1024*1024, minimumEntries: 16,
            call: { fd, attrs, buffer, size, flags in
                let path = Self.nativePath(fd)
                if path.hasSuffix("/b9"), delay.next() == 1 { _ = releaseFirst.wait(timeout: .now()+8) }
                let count = getattrlistbulk(fd, &attrs, buffer, size, flags)
                if path.hasSuffix("/b8"), count > 0 { laterFinished.increment(); releaseFirst.signal() }
                return count
            })
        let admission = ScanAdmission(limit: 1); defer { admission.shutdown() }
        let done = expectation(description: "ordered builder accepted out-of-order reads")
        let results = ReadAheadResults()
        try admission.submit(control: ScanControl(), operation: {
            let result = DiskScanner.scan(root, metadataBackend: .ordered(native), directoryConcurrency: 4)
            results.set(result); return result
        }, completion: { _ in done.fulfill() })
        await fulfillment(of: [done], timeout: 12)
        XCTAssertGreaterThan(laterFinished.value, 0)
        let result = try XCTUnwrap(results.value)
        XCTAssertEqual(Array(result.nodes), Array(original.nodes))
    }

    func testCancelledBuilderDrainsItsOpenReaderBeforeTerminalCompletion() async throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let entered = expectation(description: "read-ahead FD held"), done = expectation(description: "cancelled builder finishes")
        let gate = DispatchSemaphore(value: 0); defer { gate.signal() }
        let visits = ReadAheadCounter(), descriptor = ReadAheadCounter(), completions = ReadAheadCounter()
        let control = ScanControl(), results = ReadAheadResults()
        let native = NativeDirectoryMetadata(maximumEntries: 131_072, maximumEstimatedBytes: 32*1024*1024, minimumEntries: 16,
            call: { fd, attrs, buffer, size, flags in
                if Self.nativePath(fd).hasSuffix("/b8"), visits.next() == 1 {
                    descriptor.set(Int(fd)); entered.fulfill(); _ = gate.wait(timeout: .now()+8)
                }
                return getattrlistbulk(fd, &attrs, buffer, size, flags)
            })
        let admission = ScanAdmission(limit: 1); defer { admission.shutdown() }
        try admission.submit(control: control, operation: {
            let result = DiskScanner.scan(root, control: control, metadataBackend: .ordered(native), directoryConcurrency: 4)
            results.set(result); return result
        }, completion: { _ in completions.increment(); done.fulfill() })
        await fulfillment(of: [entered], timeout: 5)
        control.cancel(); try await Task.sleep(for: .milliseconds(50))
        XCTAssertEqual(completions.value, 0); XCTAssertGreaterThanOrEqual(fcntl(Int32(descriptor.value), F_GETFD), 0)
        gate.signal(); await fulfillment(of: [done], timeout: 10)
        XCTAssertEqual(results.value?.cancelled, true)
        XCTAssertEqual(fcntl(Int32(descriptor.value), F_GETFD), -1); XCTAssertEqual(errno, EBADF)
        XCTAssertEqual(MacScanResources.directoryIO.observation.active, 0)
    }
}

/// Lock protects the scalar shared by test/native worker callbacks.
private final class ReadAheadCounter: @unchecked Sendable {
    private let lock = NSLock(); private var stored = 0
    func increment() { lock.withLock { stored += 1 } }
    func next() -> Int { lock.withLock { stored += 1; return stored } }
    func set(_ value: Int) { lock.withLock { stored = value } }
    var value: Int { lock.withLock { stored } }
}

private final class ReadAheadResults: @unchecked Sendable {
    private let lock = NSLock(); private var stored: ScanSnapshot?
    func set(_ value: ScanSnapshot) { lock.withLock { stored = value } }
    var value: ScanSnapshot? { lock.withLock { stored } }
}
