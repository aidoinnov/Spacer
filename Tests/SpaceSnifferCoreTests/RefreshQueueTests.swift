import XCTest
@testable import SpaceSnifferCore

final class RefreshQueueTests: XCTestCase {
    func testDistinctBranchesRemainFIFOInsteadOfExpandingToTheirCommonRoot() {
        var queue = RefreshQueue()
        queue.insert("/root/b"); queue.insert("/root/a"); queue.insert("/root/b")
        XCTAssertEqual(queue.popFirst(), "/root/b")
        XCTAssertEqual(queue.popFirst(), "/root/a")
        XCTAssertNil(queue.popFirst())
    }

    func testAncestorReplacesDescendantsAtTheEndOfTheQueue() {
        var queue = RefreshQueue()
        queue.insert("/root/a/deep"); queue.insert("/root/b")
        queue.insert("/root/a"); queue.insert("/root/a/deep/again")
        XCTAssertEqual(queue.paths, ["/root/b", "/root/a"])
        queue.insert("/root")
        XCTAssertEqual(queue.paths, ["/root"])
    }

    func testCoverageUsesPathBoundariesAndLeavesUnrelatedWorkPending() {
        var queue = RefreshQueue()
        queue.insert("/root/a"); queue.insert("/root/ab")
        queue.removeCovered(by: "/root/a")
        XCTAssertEqual(queue.paths, ["/root/ab"])
        queue.insert("/root/ab/new")
        XCTAssertEqual(queue.paths, ["/root/ab"])
        queue.removeAll()
        XCTAssertTrue(queue.isEmpty)
    }
}
