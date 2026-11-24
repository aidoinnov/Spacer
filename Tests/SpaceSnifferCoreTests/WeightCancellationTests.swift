import XCTest
@testable import SpaceSnifferCore

final class WeightCancellationTests: XCTestCase {
    func testCancellationDuringLeafAssignmentStopsBeforeParentAggregationAndPreservesReader() throws {
        var snapshot = ScanSnapshot(rootPath: "/r")
        snapshot.nodes.append(DiskNode(id: 0, parent: nil, path: "/r", name: "r", isDirectory: true))
        for id in 1...10_000 {
            snapshot.nodes.append(DiskNode(id: id, parent: 0, path: "/r/\(id)", name: "\(id)", logicalBytes: Int64(id)))
            snapshot.nodes[0].children.append(id)
        }
        let reader = snapshot
        let filter = try ScanFilter("")
        let included = Array(repeating: true, count: snapshot.nodes.count)
        let control = ScanControl(); var checkpoints: [Int] = []
        let cancelled = filter.weights(in: snapshot, mode: .logical, included: included, control: control) { id in
            checkpoints.append(id)
            if id == 1024 { control.cancel() }
        }
        XCTAssertTrue(cancelled.isEmpty)
        XCTAssertEqual(checkpoints, [0, 1024])
        XCTAssertEqual(reader.nodes[10_000].logicalBytes, 10_000)
        XCTAssertEqual(reader.nodes[0].children.count, 10_000)
        let fresh = filter.weights(in: snapshot, mode: .logical, included: included)
        XCTAssertEqual(fresh[0], 50_005_000)
        XCTAssertEqual(fresh[10_000], 10_000)
        var entered = false
        XCTAssertTrue(filter.weights(in: snapshot, mode: .logical, included: included, control: control,
            leafCheckpoint: { _ in entered = true }).isEmpty)
        XCTAssertFalse(entered)
    }
}
