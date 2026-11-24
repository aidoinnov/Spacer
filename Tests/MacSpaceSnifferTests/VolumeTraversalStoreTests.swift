import XCTest
import SpaceSnifferCore
@testable import MacSpaceSniffer

@MainActor final class VolumeTraversalStoreTests: XCTestCase {
    private func settled(_ store: ScanStore, mode: ScanVolumeTraversal) async throws {
        for _ in 0..<800 {
            if !store.isScanning, !store.projectionPending, store.snapshot?.volumeCoverage?.traversal == mode { return }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTFail("store did not settle in requested mode"); throw CancellationError()
    }
    func testSwitchingModeIsolatesCacheAndReleasesPreviousSubscription() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/scope-store-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        try Data([1,2,3]).write(to: root.appendingPathComponent("file"))
        defer { try? FileManager.default.removeItem(at: root) }
        let local = ScanStore(), included = ScanStore(); defer { local.shutdown(); included.shutdown() }
        local.liveUpdates = false; included.liveUpdates = false
        local.start(root); included.setVolumeTraversal(.allVolumes); included.start(root)
        try await settled(local, mode: .selectedVolume); try await settled(included, mode: .allVolumes)
        XCTAssertEqual(local.snapshot?.fileCount, 1); XCTAssertEqual(included.snapshot?.fileCount, 1)
        local.setVolumeTraversal(.allVolumes)
        try await settled(local, mode: .allVolumes)
        for _ in 0..<300 {
            if await ScanService.shared.statistics().roots == 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let selectedStats = await ScanService.shared.statistics(); XCTAssertEqual(selectedStats.roots, 0)
        included.shutdown(); local.shutdown()
        for _ in 0..<300 {
            if await ScanService.includingMountedVolumes.statistics().roots == 0 { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        let allStats = await ScanService.includingMountedVolumes.statistics(); XCTAssertEqual(allStats.roots, 0)
    }
}
