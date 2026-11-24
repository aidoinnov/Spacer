import XCTest
@testable import SpaceSnifferCore

final class NavigationTests: XCTestCase {
    private func fixture() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("sniffer-navigation-" + UUID().uuidString).resolvingSymlinksInPath()
        try FileManager.default.createDirectory(at: root.appendingPathComponent("a/deep/inner"), withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: root.appendingPathComponent("b"), withIntermediateDirectories: true)
        for path in ["a/deep/inner/target.bin", "a/keep.txt", "b/other.txt"] {
            try Data([1, 2, 3]).write(to: root.appendingPathComponent(path))
        }
        return root
    }

    func testRemovedAncestorMovesFocusToNearestSurvivingParentAndRepairsHistory() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let old = DiskScanner.scan(root)
        let a = root.appendingPathComponent("a").path
        let deep = root.appendingPathComponent("a/deep").path
        let inner = root.appendingPathComponent("a/deep/inner").path
        let b = root.appendingPathComponent("b").path
        try FileManager.default.removeItem(atPath: deep)
        let current = DiskScanner.scan(root)
        let result = try XCTUnwrap(FilterProjection(snapshot: current, filter: ScanFilter(""), mode: .logical,
            showHidden: true, focusPath: inner, selectionPath: inner + "/target.bin", previous: old,
            history: [root.path, a, inner, a, root.path, b], historyIndex: 2, control: ScanControl()))
        XCTAssertEqual(current.nodes[result.focus].path, a)
        XCTAssertNil(result.selection)
        XCTAssertEqual(result.history, [root.path, a, root.path, b])
        XCTAssertEqual(result.historyIndex, 1)
    }

    func testFilterRemovalRepairsFocusAndClearsSelectionThenDoesNotRestoreOldFocus() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let s = DiskScanner.scan(root)
        let a = root.appendingPathComponent("a").path
        let inner = root.appendingPathComponent("a/deep/inner").path
        let result = try XCTUnwrap(FilterProjection(snapshot: s, filter: ScanFilter("*.txt"), mode: .logical,
            showHidden: true, focusPath: inner, selectionPath: inner + "/target.bin", previous: s,
            history: [root.path, a, inner], historyIndex: 2, control: ScanControl()))
        XCTAssertEqual(s.nodes[result.focus].path, a)
        XCTAssertEqual(result.history, [root.path, a]); XCTAssertEqual(result.historyIndex, 1)
        XCTAssertNil(result.selection)
        let cleared = try XCTUnwrap(FilterProjection(snapshot: s, filter: ScanFilter(""), mode: .logical,
            showHidden: true, focusPath: s.nodes[result.focus].path, selectionPath: nil, previous: s,
            history: result.history, historyIndex: result.historyIndex, control: ScanControl()))
        XCTAssertEqual(s.nodes[cleared.focus].path, a)
    }

    func testNoMatchesFallsBackToRootAndMatchingZeroByteFileCanRemainSelected() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let zero = root.appendingPathComponent("a/empty.txt")
        try Data().write(to: zero)
        let s = DiskScanner.scan(root)
        let empty = try XCTUnwrap(FilterProjection(snapshot: s, filter: ScanFilter("*.missing"), mode: .logical,
            showHidden: true, focusPath: root.appendingPathComponent("a").path, selectionPath: zero.path,
            history: [root.path, root.appendingPathComponent("a").path], historyIndex: 1, control: ScanControl()))
        XCTAssertEqual(empty.focus, 0); XCTAssertNil(empty.selection)
        XCTAssertEqual(empty.history, [root.path]); XCTAssertEqual(empty.historyIndex, 0)
        let match = try XCTUnwrap(FilterProjection(snapshot: s, filter: ScanFilter("*.txt"), mode: .logical,
            showHidden: true, focusPath: root.path, selectionPath: zero.path, control: ScanControl()))
        XCTAssertEqual(match.selection.map { s.nodes[$0].path }, zero.path)
    }

    func testRenamePreservesFocusSelectionAndHistoryUsingSameFileIdentity() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let old = DiskScanner.scan(root)
        let before = root.appendingPathComponent("a/deep/inner").path
        try FileManager.default.moveItem(at: root.appendingPathComponent("a/deep"), to: root.appendingPathComponent("a/renamed"))
        let current = DiskScanner.scan(root)
        let after = root.appendingPathComponent("a/renamed/inner").path
        let result = try XCTUnwrap(FilterProjection(snapshot: current, filter: ScanFilter(""), mode: .logical,
            showHidden: true, focusPath: before, selectionPath: before + "/target.bin", previous: old,
            history: [root.path, before], historyIndex: 1, control: ScanControl()))
        XCTAssertEqual(current.nodes[result.focus].path, after)
        XCTAssertEqual(result.selection.map { current.nodes[$0].path }, after + "/target.bin")
        XCTAssertEqual(result.history, [root.path, after]); XCTAssertEqual(result.historyIndex, 1)
    }
}
