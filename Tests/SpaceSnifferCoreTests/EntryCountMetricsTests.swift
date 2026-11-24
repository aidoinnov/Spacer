import XCTest
import Darwin
@testable import SpaceSnifferCore

final class EntryCountMetricsTests: XCTestCase {
    private static func writeCount(_ count: UInt32, to buffer: UnsafeMutableRawPointer, bytes: Int, includeAttribute: Bool = true) {
        buffer.initializeMemory(as: UInt8.self, repeating: 0, count: bytes)
        buffer.storeBytes(of: UInt32(28), as: UInt32.self)
        var attributes = attribute_set_t(); attributes.dirattr = includeAttribute ? UInt32(ATTR_DIR_ENTRYCOUNT) : 0
        buffer.storeBytes(of: attributes, toByteOffset: 4, as: attribute_set_t.self)
        buffer.storeBytes(of: count, toByteOffset: 24, as: UInt32.self)
    }
    func testValidZeroAndLargeCountsAreAvailableNotFailures() {
        for value: UInt32 in [0,96,.max] {
            let reader = NativeDirectoryMetadata(countCall: { _,_,p,n,_ in Self.writeCount(value, to: p, bytes: n); return 0 })
            var metrics = EntryCountMetrics()
            XCTAssertEqual(reader.entryCount("/fixture", control: ScanControl(), observeQuery: { metrics.record($0) }), value)
            XCTAssertEqual(metrics.calls, 1); XCTAssertEqual(metrics.failures, 0)
            XCTAssertEqual(metrics.unavailableResults, 0); XCTAssertEqual(metrics.cancelledAfterCall, 0)
        }
    }
    func testNativeFailureCapturesErrnoBeforeObserverAndCountsOneCall() {
        let reader = NativeDirectoryMetadata(countCall: { _,_,_,_,_ in errno = EACCES; return -1 })
        var metrics = EntryCountMetrics(); var captured: Int32?
        XCTAssertNil(reader.entryCount("/fixture", control: ScanControl(), observeQuery: { observation in
            errno = EINVAL; captured = observation.errorCode; metrics.record(observation)
        }))
        XCTAssertEqual(captured, EACCES); XCTAssertEqual(metrics.calls, 1); XCTAssertEqual(metrics.failures, 1)
        XCTAssertEqual(metrics.unavailableResults, 0)
    }
    func testInvalidOrMissingAttributesAreUnavailableNotApiFailures() {
        for missing in [false,true] {
            let reader = NativeDirectoryMetadata(countCall: { _,_,p,n,_ in
                Self.writeCount(96, to: p, bytes: n, includeAttribute: !missing)
                if !missing { p.storeBytes(of: UInt32(33), as: UInt32.self) }
                return 0
            })
            var metrics = EntryCountMetrics()
            XCTAssertNil(reader.entryCount("/fixture", control: ScanControl(), observeQuery: { metrics.record($0) }))
            XCTAssertEqual(metrics.calls, 1); XCTAssertEqual(metrics.failures, 0); XCTAssertEqual(metrics.unavailableResults, 1)
        }
    }
    func testCancellationBeforeQueryDoesNotInventCallAndAfterQueryCountsIt() {
        let calls = CountCounter(); let control = ScanControl(); control.cancel()
        let forbidden = NativeDirectoryMetadata(countCall: { _,_,_,_,_ in calls.increment(); return -1 })
        var metrics = EntryCountMetrics()
        XCTAssertNil(forbidden.entryCount("/fixture", control: control, observeQuery: { metrics.record($0) }))
        XCTAssertEqual(calls.value, 0); XCTAssertEqual(metrics.calls, 0)
        let later = ScanControl()
        let reader = NativeDirectoryMetadata(countCall: { _,_,p,n,_ in
            Self.writeCount(96, to: p, bytes: n); later.cancel(); return 0
        })
        XCTAssertNil(reader.entryCount("/fixture", control: later, observeQuery: { metrics.record($0) }))
        XCTAssertEqual(metrics.calls, 1); XCTAssertEqual(metrics.cancelledAfterCall, 1)
        XCTAssertEqual(metrics.failures, 0); XCTAssertEqual(metrics.unavailableResults, 0)
    }
    func testStatisticsMergeAndLegacyUnmeasuredDecode() throws {
        var left = ScanIOStatistics(); var right = ScanIOStatistics()
        left.entryCountMetrics?.record(.init(elapsedNanoseconds: 20, errorCode: nil, unavailableResult: false, cancelledAfterCall: false))
        right.entryCountMetrics?.record(.init(elapsedNanoseconds: 30, errorCode: EIO, unavailableResult: false, cancelledAfterCall: false))
        right.entryCountMetrics?.admissionCandidatesExamined = 4; right.entryCountMetrics?.admissionHintHits = 2
        left.mergeEnumeration(right)
        XCTAssertEqual(left.entryCountMetrics?.calls, 2); XCTAssertEqual(left.entryCountMetrics?.failures, 1)
        XCTAssertEqual(left.entryCountMetrics?.elapsedNanoseconds, 50)
        XCTAssertEqual(left.entryCountMetrics?.admissionCandidatesExamined, 4); XCTAssertEqual(left.entryCountMetrics?.admissionHintHits, 2)
        let data = try JSONEncoder().encode(left)
        XCTAssertEqual(try JSONDecoder().decode(ScanIOStatistics.self, from: data).entryCountMetrics, left.entryCountMetrics)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String:Any]); legacy.removeValue(forKey: "entryCountMetrics")
        let unmeasured = try JSONDecoder().decode(ScanIOStatistics.self, from: JSONSerialization.data(withJSONObject: legacy))
        XCTAssertNil(unmeasured.entryCountMetrics)
        left.mergeEnumeration(unmeasured); XCTAssertNil(left.entryCountMetrics)
        var unknown = unmeasured; unknown.mergeEnumeration(right); XCTAssertNil(unknown.entryCountMetrics)
    }
    func testRealScannerReportsActualTinySiblingQueries() throws {
        let root = try fixture(branches: 1000, files: 1); defer { try? FileManager.default.removeItem(at: root) }
        let calls = CountCounter()
        let reader = NativeDirectoryMetadata(countCall: { path, attrs, buffer, bytes, flags in
            calls.increment(); return getattrlist(path, &attrs, buffer, bytes, flags)
        })
        var statistics = ScanIOStatistics()
        let result = DiskScanner.scan(root, metadataBackend: .ordered(reader), directoryConcurrency: 4, diagnostics: { statistics = $0 })
        XCTAssertEqual(result.fileCount, 1000); XCTAssertEqual(result.issueCount, 0)
        XCTAssertEqual(calls.value, 60)
        XCTAssertEqual(statistics.entryCountMetrics?.calls, calls.value)
        XCTAssertEqual(statistics.entryCountMetrics?.admissionCandidatesExamined, 60)
        XCTAssertEqual(statistics.entryCountMetrics?.admissionHintHits, 0); XCTAssertEqual(statistics.prefetchScheduled, 0)
    }
    func testAdaptiveRootQueryAndExistingHintsHaveSeparateCounts() throws {
        let root = try fixture(branches: 64, files: 2); defer { try? FileManager.default.removeItem(at: root) }
        let calls = CountCounter()
        let reader = NativeDirectoryMetadata(countCall: { path, attrs, buffer, bytes, flags in
            calls.increment(); return getattrlist(path, &attrs, buffer, bytes, flags)
        })
        var statistics = ScanIOStatistics()
        let result = DiskScanner.scan(root, metadataBackend: .adaptive(reader), directoryConcurrency: 4, diagnostics: { statistics = $0 })
        XCTAssertEqual(result.fileCount, 128); XCTAssertEqual(result.issueCount, 0)
        XCTAssertEqual(calls.value, 1); XCTAssertEqual(statistics.entryCountMetrics?.calls, 1)
        XCTAssertEqual(statistics.entryCountMetrics?.admissionHintHits, 4)
    }
    func testDisappearedFirstCandidateDoesNotSuppressLaterUsefulSiblings() throws {
        let root = try fixture(branches: 64, files: 96); defer { try? FileManager.default.removeItem(at: root) }
        let reader = NativeDirectoryMetadata(countCall: { path, attrs, buffer, bytes, flags in
            if path.hasSuffix("/b0063") {
                try? FileManager.default.removeItem(atPath: path)
                errno = ENOENT; return -1
            }
            return getattrlist(path, &attrs, buffer, bytes, flags)
        })
        var statistics = ScanIOStatistics()
        let result = DiskScanner.scan(root, metadataBackend: .ordered(reader), directoryConcurrency: 4, diagnostics: { statistics = $0 })
        XCTAssertEqual(result.fileCount, 63*96); XCTAssertEqual(result.issueCount, 1)
        XCTAssertGreaterThan(statistics.prefetchUsed, 0)
        XCTAssertEqual(statistics.entryCountMetrics?.calls, 2)
        XCTAssertEqual(statistics.entryCountMetrics?.failures, 1)
        _ = try result.validated()
    }
    private func fixture(branches: Int, files: Int) throws -> URL {
        let root = URL(fileURLWithPath: "/private/tmp/query-metrics-"+UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        for branch in 0..<branches {
            let dir = root.appendingPathComponent(String(format: "b%04d", branch))
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for i in 0..<files { try Data([1]).write(to: dir.appendingPathComponent("f\(i)")) }
        }
        return root
    }
}
private final class CountCounter: @unchecked Sendable {
    private let lock = NSLock(); private var count = 0
    func increment() { lock.withLock { count += 1 } }
    var value: Int { lock.withLock { count } }
}
