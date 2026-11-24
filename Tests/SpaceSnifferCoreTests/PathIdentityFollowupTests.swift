import Foundation
import XCTest
@testable import SpaceSnifferCore

final class PathIdentityFollowupTests: XCTestCase {
    private func fixture(folderIdentity: String?, fileIdentity: String?) -> ScanSnapshot {
        var root = DiskNode(id: 0, parent: nil, path: "/r", name: "r", isDirectory: true,
                            logicalBytes: 2, allocatedBytes: 8192, children: [1, 3])
        root.fileIdentity = "device:root"
        var folder = DiskNode(id: 1, parent: 0, path: "/r/a", name: "a", isDirectory: true,
                              logicalBytes: 1, allocatedBytes: 4096, children: [2])
        folder.fileIdentity = folderIdentity
        var file = DiskNode(id: 2, parent: 1, path: "/r/a/file", name: "file", logicalBytes: 1, allocatedBytes: 4096)
        file.fileIdentity = fileIdentity
        var keep = DiskNode(id: 3, parent: 0, path: "/r/keep", name: "keep", logicalBytes: 1, allocatedBytes: 4096)
        keep.fileIdentity = "device:keep"
        return ScanSnapshot(rootPath: "/r", nodes: [root, folder, file, keep])
    }

    func testKnownSamePathReplacementDropsOldTagsSelectionFocusAndHistory() throws {
        // Native removed node 0x42ee60 clears selection and repairs focus/history.
        // FSEvents can coalesce remove+create: different known inode identities
        // prove the same pathname now denotes a different object.
        let old = fixture(folderIdentity: "device:old-folder", fileIdentity: "device:old-file")
        let current = fixture(folderIdentity: "device:new-folder", fileIdentity: "device:new-file")
        XCTAssertEqual(TagPolicy.reconcile(["/r/a": 4, "/r/a/file": 1], previous: old.nodes, current: current.nodes), [:])
        let filter = try ScanFilter("")
        let values = filter.weights(in: current, mode: .logical)
        for lookup in [[:], ["/r": 0, "/r/a": 1, "/r/a/file": 2]] {
            let repaired = try XCTUnwrap(NavigationState(snapshot: current, previous: old,
                included: Array(repeating: true, count: current.nodes.count), weights: values,
                focusPath: "/r/a", selectionPath: "/r/a/file", history: ["/r", "/r/a", "/r", "/r/a"],
                historyIndex: 3, control: ScanControl(), lookup: lookup))
            XCTAssertEqual(repaired.focus, 0); XCTAssertNil(repaired.selection)
            XCTAssertEqual(repaired.history, ["/r"]); XCTAssertEqual(repaired.historyIndex, 0)
        }
    }

    func testReplacementAtOldPathDoesNotHideUnambiguousRenameTarget() throws {
        let old = fixture(folderIdentity: "device:folder", fileIdentity: "device:file")
        var current = fixture(folderIdentity: "device:folder", fileIdentity: "device:replacement")
        var renamed = old.nodes[2]; renamed.id = 4; renamed.path = "/r/a/moved"; renamed.name = "moved"
        current.nodes.append(renamed); current.nodes[1].children.append(4)
        current.nodes[0].logicalBytes += 1; current.nodes[1].logicalBytes += 1
        current.nodes[0].allocatedBytes += 4096; current.nodes[1].allocatedBytes += 4096
        XCTAssertEqual(TagPolicy.reconcile(["/r/a/file": 4], previous: old.nodes, current: current.nodes), ["/r/a/moved": 4])
        let repaired = try XCTUnwrap(FilterProjection(snapshot: current, filter: ScanFilter(""), mode: .logical,
            showHidden: true, focusPath: "/r/a", selectionPath: "/r/a/file", previous: old,
            history: ["/r", "/r/a"], historyIndex: 1, control: ScanControl()))
        XCTAssertEqual(repaired.focus, 1); XCTAssertEqual(repaired.selection, 4)
    }

    func testMissingIdentityKeepsSnapshotPathFallbackAndSharedTableStaysValid() throws {
        for identities: (String?, String?) in [(nil, nil), (nil, "device:file"), ("device:file", nil), ("device:file", "device:file")] {
            let old = fixture(folderIdentity: "device:folder", fileIdentity: identities.0)
            let current = fixture(folderIdentity: "device:folder", fileIdentity: identities.1)
            XCTAssertEqual(TagPolicy.reconcile(["/r/a/file": 2], previous: old.nodes, current: current.nodes), ["/r/a/file": 2])
            let repaired = try XCTUnwrap(FilterProjection(snapshot: current, filter: ScanFilter(""), mode: .logical,
                showHidden: true, focusPath: "/r/a", selectionPath: "/r/a/file", previous: old,
                history: ["/r", "/r/a"], historyIndex: 1, control: ScanControl()))
            XCTAssertEqual(repaired.focus, 1); XCTAssertEqual(repaired.selection, 2)
        }
        let unchanged = fixture(folderIdentity: "device:folder", fileIdentity: "device:file")
        XCTAssertEqual(TagPolicy.reconcile(["/r/a/file": 2], previous: unchanged.nodes, current: unchanged.nodes), ["/r/a/file": 2])
    }
}
