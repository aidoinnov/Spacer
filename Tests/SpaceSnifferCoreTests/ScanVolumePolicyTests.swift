import XCTest
import Darwin
@testable import SpaceSnifferCore

final class ScanVolumePolicyTests: XCTestCase, @unchecked Sendable {
    func testFullInventoryBufferIsConservativelyIncomplete() {
        XCTAssertFalse(ScanVolumePolicy.hasCompleteInventory(returned: -1, capacity: 34))
        XCTAssertTrue(ScanVolumePolicy.hasCompleteInventory(returned: 0, capacity: 34))
        XCTAssertTrue(ScanVolumePolicy.hasCompleteInventory(returned: 33, capacity: 34))
        XCTAssertFalse(ScanVolumePolicy.hasCompleteInventory(returned: 34, capacity: 34))
        XCTAssertFalse(ScanVolumePolicy.hasCompleteInventory(returned: 35, capacity: 34))
    }
    func testMountBoundaryAndNewDeviceAreExcludedIncludingSameDeviceMount() {
        let policy = ScanVolumePolicy(traversal: .selectedVolume, anchor: "/work", device: 1,
            mounts: [.init(path: "/work/mount", isLocalAPFS: false), .init(path: "/work-other", isLocalAPFS: false)])
        XCTAssertNil(policy.exclusion(path: "/work/file", device: 1))
        XCTAssertEqual(policy.exclusion(path: "/work/mount", device: 1), "mounted_volume")
        XCTAssertEqual(policy.exclusion(path: "/work/mount/subtree", device: 1, isScanRoot: true), "mounted_volume")
        XCTAssertEqual(policy.exclusion(path: "/work/new", device: 2), "different_device")
        XCTAssertNil(policy.exclusion(path: "/work/mount-sibling", device: 1))
        XCTAssertFalse(policy.mountRoots.contains("/work-other"))
        let included = ScanVolumePolicy(traversal: .allVolumes, anchor: "/work", device: 1,
            mounts: [.init(path: "/work/mount", isLocalAPFS: false)])
        XCTAssertNil(included.exclusion(path: "/work/mount", device: 2))
    }

    func testSystemDataFirmlinkViewIsIncludedButDirectAliasIsExcludedInBothModes() {
        let mounts = [ScanVolumePolicy.Mount(path: "/", isLocalAPFS: true),
                      .init(path: "/System/Volumes/Data", isLocalAPFS: true), .init(path: "/Volumes/NAS", isLocalAPFS: false)]
        for mode in [ScanVolumeTraversal.selectedVolume, .allVolumes] {
            let policy = ScanVolumePolicy(traversal: mode, anchor: "/", device: 1, mounts: mounts, dataDevice: 2)
            XCTAssertNil(policy.exclusion(path: "/Users", device: 2))
            XCTAssertNil(policy.exclusion(path: "/private", device: 2))
            XCTAssertEqual(policy.exclusion(path: "/System/Volumes/Data", device: 2), "duplicate_data_view")
            XCTAssertEqual(policy.exclusion(path: "/System/Volumes/Data/Users", device: 2, isScanRoot: true), "duplicate_data_view")
            XCTAssertEqual(policy.exclusion(path: "/Volumes/NAS", device: 3), mode == .selectedVolume ? "mounted_volume" : nil)
        }
        let dataRoot = ScanVolumePolicy(traversal: .selectedVolume, anchor: "/System/Volumes/Data", device: 2, mounts: mounts)
        XCTAssertNil(dataRoot.exclusion(path: "/System/Volumes/Data", device: 2, isScanRoot: true))
        let unverified = ScanVolumePolicy(traversal: .selectedVolume, anchor: "/", device: 1, mounts: [], dataDevice: 2)
        XCTAssertEqual(unverified.exclusion(path: "/Users", device: 2), "different_device")
    }

    func testNativeSystemInventoryKeepsUsersAndRejectsDataAlias() throws {
        var root = stat(); XCTAssertEqual(lstat("/", &root), 0)
        let policy = ScanVolumePolicy.discover(traversal: .selectedVolume, anchor: "/", device: root.st_dev)
        XCTAssertTrue(policy.inventoryComplete)
        guard policy.mountRoots.contains("/System/Volumes/Data") else { throw XCTSkip("no macOS split System/Data volume") }
        for path in ["/Users", "/private"] {
            var value = stat(); XCTAssertEqual(lstat(path, &value), 0)
            XCTAssertNil(policy.exclusion(path: path, device: value.st_dev))
        }
    }

    private func fixture() throws -> URL {
        let root = URL(fileURLWithPath: "/private/tmp/scope-unit-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a"), withIntermediateDirectories: true)
        try Data([1,2,3]).write(to: root.appendingPathComponent("a/file"))
        return root.standardizedFileURL
    }

    func testCoverageIsBoundedAndLegacyJSONAndSNSDoNotInventScope() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var snapshot = DiskScanner.scan(root)
        XCTAssertEqual(snapshot.volumeCoverage?.traversal, .selectedVolume)
        XCTAssertEqual(DiskScanner.scan(root, volumeTraversal: .allVolumes).volumeCoverage?.traversal, .allVolumes)
        var coverage = ScanVolumeCoverage(traversal: .selectedVolume)
        for i in 0..<503 { coverage.exclude(root.path + "/boundary\(i)", reason: "mounted_volume") }
        XCTAssertEqual(coverage.excludedCount, 503); XCTAssertEqual(coverage.exclusions.count, 500)
        snapshot.volumeCoverage = coverage
        XCTAssertTrue(ScanWork.requiresRootRefresh(snapshot)); _ = try snapshot.validated()
        let encoded = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(ScanSnapshot.self, from: encoded)
        XCTAssertEqual(decoded.volumeCoverage, coverage)
        var legacy = try XCTUnwrap(JSONSerialization.jsonObject(with: encoded) as? [String: Any]); legacy.removeValue(forKey: "volumeCoverage")
        XCTAssertNil(try JSONDecoder().decode(ScanSnapshot.self, from: JSONSerialization.data(withJSONObject: legacy)).volumeCoverage)
        let file = root.deletingLastPathComponent().appendingPathComponent(UUID().uuidString + ".sns")
        defer { try? FileManager.default.removeItem(at: file) }
        try SNSSnapshot.encode(snapshot).write(to: file)
        XCTAssertNil(try ArtifactTransfer.load(file).volumeCoverage)
    }

    func testScopedMergeReplacesExclusionsAndRejectsModeMixOrTruncation() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var original = DiskScanner.scan(root)
        original.volumeCoverage?.exclude(root.path + "/old-boundary", reason: "mounted_volume")
        original.volumeCoverage?.exclude(root.path + "/a/removed-boundary", reason: "mounted_volume")
        var branch = DiskScanner.scan(root.appendingPathComponent("a"), scopeRoot: root)
        branch.volumeCoverage?.exclude(root.path + "/a/new-boundary", reason: "mounted_volume")
        let merged = try XCTUnwrap(SnapshotTree.replacing(original, with: branch, control: ScanControl()))
        XCTAssertEqual(merged.volumeCoverage?.exclusions.map(\.path), [root.path + "/old-boundary",root.path + "/a/new-boundary"])
        XCTAssertEqual(merged.volumeCoverage?.excludedCount, 2)
        branch.volumeCoverage = ScanVolumeCoverage(traversal: .allVolumes)
        XCTAssertNil(SnapshotTree.replacing(original, with: branch, control: ScanControl()))
        original.volumeCoverage?.excludedCount = 501
        XCTAssertTrue(ScanWork.requiresRootRefresh(original))
        XCTAssertNil(SnapshotTree.replacing(original, with: branch, control: ScanControl()))
    }
}
