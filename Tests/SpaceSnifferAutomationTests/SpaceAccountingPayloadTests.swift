import XCTest
import SpaceSnifferCore
@testable import SpaceSnifferAutomation

final class SpaceAccountingPayloadTests: XCTestCase {
    func testScopeAndResidualRemainExplicit() throws {
        var snapshot = ScanSnapshot(rootPath: "/volume", nodes: [DiskNode(id: 0, parent: nil, path: "/volume", name: "volume", isDirectory: true, allocatedBytes: 300)])
        snapshot.isVolumeRoot = true; snapshot.volumeTotal = 1000; snapshot.volumeFree = 200
        let value = SpaceAccountingPayload.make(snapshot: snapshot, offline: false)
        guard case let .object(fields) = value else { return XCTFail("Expected live volume observation") }
        XCTAssertEqual(fields["system_used_bytes"], .integer(800))
        XCTAssertEqual(fields["unattributed_bytes"], .integer(500))
        XCTAssertEqual(fields["volume_metadata_timing"], .string("captured_at_scan_start"))
        XCTAssertEqual(fields["coverage_percentage_available"], .bool(false))
        XCTAssertEqual(SpaceAccountingPayload.make(snapshot: snapshot, offline: true), .null)
        snapshot.isVolumeRoot = false
        XCTAssertEqual(SpaceAccountingPayload.make(snapshot: snapshot, offline: false), .null)
        XCTAssertEqual(SpaceAccountingPayload.make(snapshot: nil, offline: false), .null)
    }
}
