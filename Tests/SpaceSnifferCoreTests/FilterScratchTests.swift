import XCTest
@testable import SpaceSnifferCore

final class FilterScratchTests: XCTestCase {
    private func fixture() -> ScanSnapshot {
        var s = ScanSnapshot(rootPath: "/r", nodes: [
            DiskNode(id: 0, parent: nil, path: "/r", name: "r", isDirectory: true, children: [1, 3]),
            DiskNode(id: 1, parent: 0, path: "/r/a", name: "a", isDirectory: true, children: [2]),
            DiskNode(id: 2, parent: 1, path: "/r/a/zero.bin", name: "zero.bin"),
            DiskNode(id: 3, parent: 0, path: "/r/b.txt", name: "b.txt", logicalBytes: 9)])
        s.tags = ["/r/a": 1]; s.nodes[1].nativeAttributes = 2
        return s
    }
    func testReusedContextAgreesWithFreshPassAcrossTagsHiddenFoldersAndCancellation() throws {
        let scratch = FilterScratch(); let initial = fixture()
        var changed = initial; changed.tags = ["/r/b.txt": 4]; changed.nodes[1].nativeAttributes = 0
        for snapshot in [initial, changed, initial, changed] {
            for text in [":red", ":green", "\\a", "|\\a", "", "*.txt", ":attr:hidden"] {
                let filter = try ScanFilter(text)
                for showHidden in [true, false] {
                    let expected = filter.membership(in: snapshot, showHidden: showHidden)
                    let actual = scratch.membership(filter: filter, snapshot: snapshot, showHidden: showHidden, control: ScanControl())
                    XCTAssertEqual(actual, expected, text)
                    let cancelled = ScanControl(); cancelled.cancel()
                    XCTAssertNil(scratch.membership(filter: filter, snapshot: snapshot, showHidden: showHidden, control: cancelled))
                }
            }
        }
    }
    func testScratchCannotMutateFrozenPublishedEvaluationAndEvictsOversizedStorage() throws {
        let scratch = FilterScratch(retentionLimit: 4)
        let source = fixture(); let filter = try ScanFilter(":red")
        let frozen = try XCTUnwrap(ProjectionEvaluation(snapshot: source, filter: filter, mode: .logical,
            showHidden: true, control: ScanControl(), scratch: scratch))
        var larger = source
        for id in 4..<2000 { larger.nodes.append(DiskNode(id: id, parent: 0, path: "/r/\(id).txt", name: "\(id).txt", logicalBytes: 3)); larger.nodes[0].children.append(id) }
        _ = scratch.membership(filter: try ScanFilter(":green"), snapshot: larger, showHidden: false, control: ScanControl())
        XCTAssertEqual(scratch.retainedBytes, 0)
        XCTAssertTrue(frozen.included[2]); XCTAssertFalse(frozen.included[3]); XCTAssertEqual(frozen.weights[0], 0)
        _ = scratch.membership(filter: try ScanFilter("\\a"), snapshot: source, showHidden: true, control: ScanControl())
        XCTAssertTrue(frozen.included[2]); XCTAssertFalse(frozen.included[3])
    }
}
