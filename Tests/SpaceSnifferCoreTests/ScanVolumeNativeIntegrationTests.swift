import XCTest
@testable import SpaceSnifferCore

/// Explicitly provisioned owned images; ordinary unit runs never create mounts.
final class ScanVolumeNativeIntegrationTests: XCTestCase, @unchecked Sendable {
    private func fixture() throws -> URL {
        guard let manifest = ProcessInfo.processInfo.environment["SNIFFER_SCOPE_MANIFEST"] else { throw XCTSkip("owned nested-volume fixture not provisioned") }
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: URL(fileURLWithPath: manifest))) as? [String: Any])
        let path = try XCTUnwrap(json["root"] as? String)
        guard path.hasPrefix("/private/tmp/sniffer-scope-native-"), json["removed"] as? Bool == false else { throw SnapshotError.invalid }
        return URL(fileURLWithPath: path).standardizedFileURL
    }

    func testDefaultSkipsMountedTreeAndOptInIncludesBothNestedVolumes() throws {
        let root = try fixture(); var localIO = ScanIOStatistics(), allIO = ScanIOStatistics()
        let local = DiskScanner.scan(root, metadataBackend: .automatic(.orderedScan), diagnostics: { localIO = $0 })
        let all = DiskScanner.scan(root, metadataBackend: .automatic(.orderedScan), volumeTraversal: .allVolumes, diagnostics: { allIO = $0 })
        XCTAssertEqual(local.fileCount, 100); XCTAssertEqual(local.folderCount, 5)
        XCTAssertEqual(local.nodes[0].logicalBytes, 300); XCTAssertEqual(local.issueCount, 0)
        XCTAssertEqual(local.volumeCoverage?.exclusions, [.init(path: root.path + "/foreign", reason: "mounted_volume")])
        XCTAssertFalse(local.nodes.contains { SnapshotTree.contains(root.path + "/foreign", $0.path) })
        XCTAssertEqual(localIO.openDirectoryCalls, 5)
        XCTAssertEqual(localIO.statCalls, 5) // root+four local branches; no target lstat of the known mount
        XCTAssertEqual(all.fileCount, 6100); XCTAssertEqual(all.folderCount, 37)
        XCTAssertEqual(all.nodes[0].logicalBytes, 30300); XCTAssertEqual(all.issueCount, 0)
        XCTAssertEqual(all.volumeCoverage?.excludedCount, 0); XCTAssertEqual(allIO.openDirectoryCalls, 37)
        _ = try local.validated(); _ = try all.validated()
    }

    func testMountedRootCanBeSelectedButAnchoredScopedRescanCannotEscape() throws {
        let root = try fixture(); let foreign = root.appendingPathComponent("foreign")
        let selected = DiskScanner.scan(foreign)
        XCTAssertEqual(selected.fileCount, 5000); XCTAssertEqual(selected.folderCount, 21)
        XCTAssertEqual(selected.volumeCoverage?.excludedCount, 1)
        XCTAssertEqual(DiskScanner.scan(foreign.appendingPathComponent("nested")).fileCount, 1000)
        for path in [foreign, foreign.appendingPathComponent("b0")] {
            var stats = ScanIOStatistics()
            let blocked = DiskScanner.scan(path, metadataBackend: .automatic(.orderedScan), scopeRoot: root, diagnostics: { stats = $0 })
            XCTAssertTrue(blocked.nodes.isEmpty); XCTAssertEqual(blocked.volumeCoverage?.excludedCount, 1)
            XCTAssertEqual(stats.openDirectoryCalls, 0)
        }
        let full = DiskScanner.scan(root, volumeTraversal: .allVolumes)
        let branch = DiskScanner.scan(foreign, volumeTraversal: .allVolumes, scopeRoot: root)
        XCTAssertEqual(branch.volumeTotal, full.volumeTotal)
        XCTAssertFalse(branch.isVolumeRoot)
        let merged = try XCTUnwrap(SnapshotTree.replacing(full, with: branch, control: ScanControl()))
        XCTAssertEqual(merged.fileCount, 6100); XCTAssertEqual(merged.nodes[0].logicalBytes, 30300)
    }

    func testWatcherExcludedEventAndFocusCannotStartAnOutOfScopeScan() async throws {
        let root = try fixture(); let probe = ScopeMonitorProbe(); let admission = ScanAdmission(limit: 1)
        defer { admission.shutdown() }
        let service = ScanService(admission: admission, scanner: { url, control, progress, heartbeat in
            DiskScanner.scan(url, control: control, scopeRoot: root, progress: progress, heartbeat: heartbeat)
        }, monitorFactory: { _, deliver in probe.set(deliver); return NSObject() })
        let lease = await service.subscribe(root)
        defer { Task { await service.unsubscribe(lease.id, rootPath: lease.rootPath) } }
        let complete = try await withThrowingTaskGroup(of: ScanUpdate.self) { group in
            group.addTask {
                for await value in lease.updates where !value.isScanning { return value }
                throw CancellationError()
            }
            group.addTask { try await Task.sleep(for: .seconds(8)); throw CancellationError() }
            defer { group.cancelAll() }; return try await group.next()!
        }
        XCTAssertEqual(complete.snapshot.fileCount, 100)
        let request = await service.requestFocusRescan(subscription: lease, scope: root.path + "/foreign")
        XCTAssertNil(request)
        await probe.send([.init(path: root.path + "/foreign/b0/f00000", isDirectory: false, mustRescan: false)])
        let stats = await service.statistics(); XCTAssertEqual(stats.scanStarts, 1)
        await service.unsubscribe(lease.id, rootPath: lease.rootPath)
    }
}

private final class ScopeMonitorProbe: @unchecked Sendable {
    private let lock = NSLock()
    private var deliver: ScanService.MonitorDelivery?
    func set(_ value: @escaping ScanService.MonitorDelivery) { lock.withLock { deliver = value } }
    func send(_ values: [PathChange]) async { let action = lock.withLock { deliver }; await action?(values) }
}
