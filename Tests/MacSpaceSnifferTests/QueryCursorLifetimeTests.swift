import XCTest
@testable import MacSpaceSniffer
@testable import SpaceSnifferAutomation
import SpaceSnifferCore

@MainActor final class QueryCursorLifetimeTests: XCTestCase {
    func testPublishingRevisionAndWindowShutdownReleaseCursorContext() throws {
        let store = ScanStore()
        store.snapshot = ScanSnapshot(rootPath: "/r", nodes: [
            DiskNode(id: 0, parent: nil, path: "/r", name: "r", isDirectory: true, children: [1]),
            DiskNode(id: 1, parent: 0, path: "/r/one", name: "one", logicalBytes: 1)])
        store.weights = [1,1]
        let first = try XCTUnwrap(store.automationContext)
        _ = try store.automationQueries.query(context: first, arguments: ["traversal": .string("subtree"), "budget": .int(1)])
        weak let firstLease = store.automationQueries.contextLeaseWitness
        XCTAssertNotNil(firstLease)
        store.projectionRevision = UUID()
        XCTAssertNil(firstLease); XCTAssertEqual(store.automationQueries.statistics.cursors, 0)
        let second = try XCTUnwrap(store.automationContext)
        _ = try store.automationQueries.query(context: second, arguments: ["traversal": .string("subtree"), "budget": .int(1)])
        weak let secondLease = store.automationQueries.contextLeaseWitness
        XCTAssertNotNil(secondLease); store.shutdown()
        XCTAssertNil(secondLease); XCTAssertEqual(store.automationQueries.statistics.cursors, 0)
        XCTAssertEqual(store.automationQueries.statistics.activePages, 0)
        XCTAssertThrowsError(try store.automationQueries.query(context: second, arguments: ["traversal": .string("subtree")])) { error in
            XCTAssertEqual((error as? ControlError)?.code, "cancelled")
        }
        XCTAssertEqual(first.snapshot.nodes[1].path, "/r/one", "Previously issued immutable readers remain valid")
    }
}
