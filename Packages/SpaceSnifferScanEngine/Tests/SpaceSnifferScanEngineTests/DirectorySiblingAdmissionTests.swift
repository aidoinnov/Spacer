import XCTest
@testable import SpaceSnifferScanEngine

final class DirectorySiblingAdmissionTests: XCTestCase {
    func testNegativeSamplesExpireAndParentChangesResetAdmission() {
        var state = DirectorySiblingAdmission<Int>(recheckAfter: 3)
        XCTAssertNil(state.decision(for: 1)); state.record(false, for: 1)
        for _ in 0..<3 { XCTAssertEqual(state.decision(for: 1), false) }
        XCTAssertNil(state.decision(for: 1)); state.record(true, for: 1)
        for _ in 0..<100 { XCTAssertEqual(state.decision(for: 1), true) }
        XCTAssertNil(state.decision(for: 2)); state.record(false, for: 2)
        XCTAssertNil(state.decision(for: 1))
    }
}
