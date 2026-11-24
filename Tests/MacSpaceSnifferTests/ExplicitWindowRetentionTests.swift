import Foundation
import XCTest
@testable import MacSpaceSniffer

@MainActor final class ExplicitWindowRetentionTests: XCTestCase {
    func testOnlyHiddenOwnersAreRetainedAndAutomaticTerminationIsBalanced() {
        let calls = RetentionCalls()
        let owner = ExplicitWindowRetention<NSObject, NSObject>(begin: { calls.begin() }, end: { calls.end() })
        var window: NSObject? = NSObject(); var model: NSObject? = NSObject()
        weak var weakWindow = window; weak var weakModel = model
        owner.retain("one", window: window!, model: model!)
        owner.retain("one", window: window!, model: model!)
        owner.retain("two", window: NSObject(), model: NSObject())
        window = nil; model = nil
        XCTAssertNotNil(weakWindow); XCTAssertNotNil(weakModel); XCTAssertTrue(owner.hasWindows)
        XCTAssertEqual(calls.values.0, 1)
        owner.release("one"); XCTAssertNil(weakWindow); XCTAssertNil(weakModel)
        XCTAssertEqual(calls.values.1, 0)
        owner.release("two"); owner.release("two"); owner.removeAll()
        XCTAssertFalse(owner.hasWindows); XCTAssertEqual(calls.values.1, 1)
        owner.retain("three", window: NSObject(), model: NSObject()); owner.removeAll()
        XCTAssertEqual(calls.values.0, 2); XCTAssertEqual(calls.values.1, 2)
    }
    func testOwnerDestructionReleasesItsTerminationLease() {
        let calls = RetentionCalls()
        var owner: ExplicitWindowRetention<NSObject, NSObject>? = ExplicitWindowRetention(begin: { calls.begin() }, end: { calls.end() })
        owner?.retain("one", window: NSObject(), model: NSObject()); owner = nil
        XCTAssertEqual(calls.values.0, 1); XCTAssertEqual(calls.values.1, 1)
    }
}
private final class RetentionCalls: @unchecked Sendable {
    private let lock = NSLock(); private var begins = 0; private var ends = 0
    func begin() { lock.withLock { begins += 1 } }
    func end() { lock.withLock { ends += 1 } }
    var values: (Int,Int) { lock.withLock { (begins,ends) } }
}
