import XCTest
import SnifferTestSupport
@testable import SpaceSnifferCore

final class PoolOwnershipTests: XCTestCase, @unchecked Sendable {
    func testAllCandidateReadersStayFrozenWhileWriterResetsAndEvicts() async throws {
        for kind in PoolCandidate.Kind.allCases {
            let pool = PoolCandidate(kind); let base = Array(OptimizationFixture.metadata(files: 2000, shape: .wide).nodes)
            let frozen = pool.build(base)
            let reader = Task.detached { for _ in 0..<20 { XCTAssertEqual(frozen.materialized(), base) }; return true }
            for pass in 1...6 {
                let changed = base.map { node -> DiskNode in
                    var node = node; node.name += "-\(pass)"; node.path += "-\(pass)"; node.logicalBytes += Int64(pass)
                    node.issue = pass % 2 == 0 ? "issue" : nil; node.nativeFlags = UInt8(pass); node.children = []
                    return node
                }
                let current = pool.build(changed); XCTAssertEqual(current.materialized(), changed)
                pool.evict(); XCTAssertEqual(pool.statistics().retainedCharge, 0)
                XCTAssertEqual(frozen.materialized(), base)
            }
            let complete = await reader.value; XCTAssertTrue(complete)
            if kind != .current { XCTAssertGreaterThan(pool.statistics().busyExclusions, 0) }
            pool.evict()
        }
    }
    func testReaderFreeCandidatesActuallyReuseAndResetAllFields() {
        let input = Array(OptimizationFixture.metadata(files: 1000, shape: .wide).nodes)
        for kind in [PoolCandidate.Kind.pages, .nodes] {
            let pool = PoolCandidate(kind)
            autoreleasepool { let value = pool.build(input); XCTAssertEqual(value.materialized(), input) }
            let changed = input.map { node -> DiskNode in var node = node; node.issue = "different"; node.nativeAttributes = 2; node.nativeFlags = 16; node.fileIdentity = "new"; return node }
            let value = pool.build(changed)
            XCTAssertGreaterThan(pool.statistics().hits, 0); XCTAssertEqual(value.materialized(), changed)
            XCTAssertLessThanOrEqual(pool.statistics().retainedCharge, 4_194_304); pool.evict()
        }
    }
    func testScratchGlobalBudgetIdlePressureAndOversizedEviction() throws {
        let input = OptimizationFixture.metadata(files: 2048)
        let filter = try ScanFilter(":red")
        let owners = (0..<80).map { _ in FilterScratch() }
        for owner in owners { _ = owner.membership(filter: filter, snapshot: input, showHidden: false, control: ScanControl()) }
        let before = ScratchResources.statistics()
        XCTAssertLessThanOrEqual(before.chargedBytes, before.limit); XCTAssertLessThanOrEqual(before.retainedBytes, before.limit)
        XCTAssertLessThanOrEqual(before.owners, 64)
        ScratchBudget.shared.pressure()
        XCTAssertEqual(ScratchResources.statistics().retainedBytes, 0)
        for owner in owners { XCTAssertEqual(owner.retainedBytes, 0) }
        let stopped = ScanControl(); stopped.cancel()
        XCTAssertNil(owners[0].membership(filter: filter, snapshot: input, showHidden: false, control: stopped))
    }
}
