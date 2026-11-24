import AppKit
import XCTest
import SpaceSnifferCore
@testable import MacSpaceSniffer

@MainActor final class MapMotionTests: XCTestCase {
    func testChangedLayoutActuallyInvokesReduceMotionAndKeepsLatestTarget() {
        let root = DiskNode(id: 0, parent: nil, path: "/motion", name: "motion", isDirectory: true, children: [1])
        let node = DiskNode(id: 1, parent: 0, path: "/motion/a", name: "a", logicalBytes: 10)
        let store = ScanStore(); store.snapshot = ScanSnapshot(rootPath: root.path, nodes: [root,node]); store.weights = [10,10]
        let canvas = MapCanvas(store: store); var reduceCalls = 0
        canvas.reduceMotion = { reduceCalls += 1; return true }
        func item(_ x: Int) -> MapItem {
            MapItem(tile: TreemapTile(id: 1, rect: CGRect(x: x, y: 0, width: 100, height: 100), expanded: false, level: 1), node: node,
                parentPath: root.path, sizeText: "10 B", sizeWidth: 20, tag: 0, category: .other, displayBytes: 10)
        }
        canvas.install([item(0)]); XCTAssertEqual(reduceCalls, 0)
        canvas.install([item(50)]) // A different rectangle, so sameLayout cannot bypass the motion policy.
        XCTAssertEqual(reduceCalls, 1); XCTAssertEqual(canvas.presentationStatistics["items"], 1)
        XCTAssertEqual(canvas.presentationStatistics["transition_active"], 0); XCTAssertEqual(canvas.presentationStatistics["timer_active"], 0)
        canvas.install([item(50)]); XCTAssertEqual(reduceCalls, 1)
        canvas.viewDidMoveToWindow(); store.shutdown()
    }
}
