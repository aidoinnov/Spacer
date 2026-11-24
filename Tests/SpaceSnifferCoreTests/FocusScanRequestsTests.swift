import XCTest
@testable import SpaceSnifferCore

final class FocusScanRequestsTests: XCTestCase {
    func testOwnerReplacementRetiresOnlyItsExactTicketAndPreservesFIFO() {
        let incarnation = UUID(); var policy = FocusScanRequests(rootPath: "/root", incarnation: incarnation)
        let a = UUID(), b = UUID()
        let first = policy.replace(owner: a, scope: "/root/a", targetIdentity: "1:2")
        XCTAssertEqual(policy.takeNext(), first)
        let other = policy.replace(owner: b, scope: "/root/b", targetIdentity: nil)
        let replacement = policy.replace(owner: a, scope: "/root/a/child", targetIdentity: "1:3")
        XCTAssertFalse(policy.isCurrent(first)); XCTAssertTrue(policy.isCurrent(other))
        XCTAssertFalse(policy.cancel(first)) // Cannot cancel the replacement with an old receipt.
        XCTAssertNil(policy.takeNext()) // Active I/O must drain before any other scope.
        policy.finish(first)
        XCTAssertEqual(policy.takeNext(), other); policy.finish(other)
        XCTAssertEqual(policy.takeNext(), replacement); policy.finish(replacement)
        XCTAssertTrue(policy.isEmpty); XCTAssertNil(policy.active)
    }
    func testOwnerCancelDoesNotCancelAnotherOwnerAndRootResetInvalidatesAll() {
        var policy = FocusScanRequests(rootPath: "/root", incarnation: UUID())
        let a=UUID(), b=UUID()
        let active = policy.replace(owner:a,scope:"/root/a",targetIdentity:nil)
        XCTAssertEqual(policy.takeNext(),active)
        let other = policy.replace(owner:b,scope:"/root/b",targetIdentity:nil)
        XCTAssertFalse(policy.cancel(owner:b)); XCTAssertTrue(policy.isCurrent(active)); XCTAssertFalse(policy.isCurrent(other))
        policy.reset(); XCTAssertFalse(policy.isCurrent(active)); XCTAssertNil(policy.takeNext())
        policy.finish(active); XCTAssertNil(policy.takeNext())
        var recreated = FocusScanRequests(rootPath:"/root",incarnation:UUID())
        XCTAssertFalse(recreated.cancel(active))
    }
    func testPendingReplacementHasOneOwnerSlotAndStablePosition() {
        var policy=FocusScanRequests(rootPath:"/root",incarnation:UUID()); let a=UUID(), b=UUID()
        _ = policy.replace(owner:a,scope:"/root/a",targetIdentity:nil)
        let other=policy.replace(owner:b,scope:"/root/b",targetIdentity:nil)
        var latest: FocusScanRequest!
        for _ in 0..<100 { latest=policy.replace(owner:a,scope:"/root/a/new",targetIdentity:nil) }
        XCTAssertEqual(policy.takeNext(),latest); policy.finish(latest)
        XCTAssertEqual(policy.takeNext(),other); policy.finish(other)
        XCTAssertNil(policy.takeNext())
    }
}
