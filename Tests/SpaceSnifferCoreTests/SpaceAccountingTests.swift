import XCTest
@testable import SpaceSnifferCore

final class SpaceAccountingTests: XCTestCase {
    func testAllVolumeTotalsAreNotSubtractedFromOneVolumesUsedSpace() throws {
        var snapshot = ScanSnapshot(rootPath: "/volume", nodes: [DiskNode(id: 0, parent: nil, path: "/volume", name: "volume", isDirectory: true, allocatedBytes: 300)])
        snapshot.volumeTotal = 1000; snapshot.volumeFree = 200; snapshot.isVolumeRoot = true
        snapshot.volumeCoverage = ScanVolumeCoverage(traversal: .selectedVolume)
        XCTAssertNotNil(SpaceAccounting(snapshot: snapshot, offline: false))
        snapshot.volumeCoverage = ScanVolumeCoverage(traversal: .allVolumes)
        XCTAssertNil(SpaceAccounting(snapshot: snapshot, offline: false))
    }
    func testLiveEquationAndPresentationNeverDoubleCountObservedData() throws {
        let value = try XCTUnwrap(SpaceAccounting(totalBytes: 1000, freeBytes: 200, observedPhysicalBytes: 300))
        XCTAssertEqual(value.systemUsedBytes, 800); XCTAssertEqual(value.unattributedBytes, 500)
        XCTAssertEqual(value.unclampedResidualBytes, 500); XCTAssertEqual(value.diagnostics, [])
        for free in [false, true] { for unknown in [false, true] {
            let view = try XCTUnwrap(value.presentation(isVoidFilter: true, showFreeSpace: free, showUnknownSpace: unknown))
            XCTAssertEqual(view.dataPhysicalBytes, 300)
            XCTAssertEqual(view.freeSpaceBytes, free ? 200 : 0)
            XCTAssertEqual(view.unattributedSpaceBytes, unknown ? 500 : 0)
            XCTAssertEqual(view.totalAreaBytes, 300 + (free ? 200 : 0) + (unknown ? 500 : 0))
        } }
        XCTAssertEqual(value.observedPhysicalBytes, 300) // Presentation never mutates data accounting.
        let filtered = try XCTUnwrap(value.presentation(isVoidFilter: false, showFreeSpace: true, showUnknownSpace: true, dataPhysicalBytes: 123))
        XCTAssertEqual(filtered.dataPhysicalBytes, 123); XCTAssertEqual(filtered.totalAreaBytes, 123)
        XCTAssertEqual(filtered.freeSpaceBytes, 0); XCTAssertEqual(filtered.unattributedSpaceBytes, 0)
    }
    func testOverlappingOrUnavailableOSObservationsRemainExplicit() throws {
        let excess = try XCTUnwrap(SpaceAccounting(totalBytes: 1000, freeBytes: 300, observedPhysicalBytes: 900))
        XCTAssertEqual(excess.systemUsedBytes, 700); XCTAssertEqual(excess.unclampedResidualBytes, -200)
        XCTAssertEqual(excess.unattributedBytes, 0); XCTAssertEqual(excess.diagnostics, [.observedExceedsUsed])
        let stale = try XCTUnwrap(SpaceAccounting(totalBytes: 100, freeBytes: 200, observedPhysicalBytes: 20))
        XCTAssertEqual(stale.systemUsedBytes, -100); XCTAssertEqual(stale.unattributedBytes, 0)
        XCTAssertEqual(stale.diagnostics, [.freeExceedsTotal, .observedExceedsUsed])
        let missing = try XCTUnwrap(SpaceAccounting(totalBytes: 0, freeBytes: 0, observedPhysicalBytes: 20))
        XCTAssertEqual(missing.diagnostics, [.zeroCapacity, .observedExceedsUsed]); XCTAssertEqual(missing.unattributedBytes, 0)
        XCTAssertNil(SpaceAccounting(totalBytes: -1, freeBytes: 0, observedPhysicalBytes: 0))
        XCTAssertNil(SpaceAccounting(totalBytes: 1, freeBytes: -1, observedPhysicalBytes: 0))
        XCTAssertNil(SpaceAccounting(totalBytes: 1, freeBytes: 0, observedPhysicalBytes: -1))
    }
    func testSignedExtremesCannotWrapResidualOrPresentationArea() throws {
        let maximum = try XCTUnwrap(SpaceAccounting(totalBytes: .max, freeBytes: 0, observedPhysicalBytes: 0))
        XCTAssertEqual(maximum.unattributedBytes, .max)
        XCTAssertEqual(maximum.presentation(isVoidFilter: true, showFreeSpace: true, showUnknownSpace: true)?.totalAreaBytes, .max)
        let underflow = try XCTUnwrap(SpaceAccounting(totalBytes: 0, freeBytes: .max, observedPhysicalBytes: .max))
        XCTAssertNil(underflow.unclampedResidualBytes); XCTAssertEqual(underflow.unattributedBytes, 0)
        XCTAssertTrue(underflow.diagnostics.contains(.residualUnderflow))
        let area = try XCTUnwrap(underflow.presentation(isVoidFilter: true, showFreeSpace: true, showUnknownSpace: true))
        XCTAssertNil(area.totalAreaBytes); XCTAssertTrue(area.overflowed)
        XCTAssertNil(underflow.presentation(isVoidFilter: true, showFreeSpace: false, showUnknownSpace: false, dataPhysicalBytes: -1))
    }
    func testScopeOfflineTypesAndAccessErrorsDoNotInventAttribution() throws {
        var snapshot = ScanSnapshot(rootPath: "/volume", nodes: [DiskNode(id: 0, parent: nil, path: "/volume", name: "volume", isDirectory: true, allocatedBytes: 300)])
        snapshot.volumeTotal = 1000; snapshot.volumeFree = 200
        XCTAssertNil(SpaceAccounting(snapshot: snapshot, offline: false)) // A folder is not the whole volume.
        snapshot.isVolumeRoot = true
        let clean = try XCTUnwrap(SpaceAccounting(snapshot: snapshot, offline: false))
        snapshot.issueCount = 501; snapshot.issues = ["/volume/protected: denied"]
        let denied = try XCTUnwrap(SpaceAccounting(snapshot: snapshot, offline: false))
        XCTAssertEqual(clean, denied) // Unknown residual does not mean permission-denied bytes.
        snapshot.nodes[0].nativeType = 1
        for kind: UInt8 in [4, 5, 6] {
            var stored = DiskNode(id: snapshot.nodes.count, parent: 0, path: "/volume/stored-\(kind)", name: "stored", logicalBytes: 999, allocatedBytes: 999)
            stored.nativeType = kind; snapshot.nodes.append(stored)
        }
        XCTAssertNil(SpaceAccounting(snapshot: snapshot, offline: true))
        XCTAssertEqual(snapshot.nodes[0].allocatedBytes, 300)
        snapshot.nodes = []; XCTAssertNil(SpaceAccounting(snapshot: snapshot, offline: false))
    }
}
