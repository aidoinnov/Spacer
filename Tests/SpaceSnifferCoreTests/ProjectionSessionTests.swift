import XCTest
@testable import SpaceSnifferCore

final class ProjectionSessionTests: XCTestCase, @unchecked Sendable {
    private func fixture() -> ScanSnapshot {
        var s = ScanSnapshot(rootPath: "/r", nodes: [
            DiskNode(id: 0, parent: nil, path: "/r", name: "r", isDirectory: true, children: [1, 4]),
            DiskNode(id: 1, parent: 0, path: "/r/a", name: "a", isDirectory: true, children: [2, 3]),
            DiskNode(id: 2, parent: 1, path: "/r/a/zero.bin", name: "zero.bin"),
            DiskNode(id: 3, parent: 1, path: "/r/a/keep.bin", name: "keep.bin", logicalBytes: 7, allocatedBytes: 4096),
            DiskNode(id: 4, parent: 0, path: "/r/b.txt", name: "b.txt", logicalBytes: 11, allocatedBytes: 8192)])
        s.nodes[1].nativeAttributes = 2; s.tags = ["/r/a": 1]
        return s
    }
    @MainActor private func run(_ session: ProjectionSession, source: ProjectionSource, text: String = "*.bin",
        fallback: ScanFilter? = nil, mode: SizeMode = .logical, hidden: Bool = true,
        focus: String? = "/r/a", selection: String? = "/r/a/zero.bin", previous: ScanSnapshot? = nil) async -> ProjectionOutcome {
        let request = ProjectionRequest(source: source, filterText: text, fallbackFilter: fallback ?? (try! ScanFilter("")),
            mode: mode, showHidden: hidden, focusPath: focus, selectionPath: selection,
            previous: previous, history: ["/r", "/r/a", "/missing"], historyIndex: 2)
        return await withCheckedContinuation { continuation in
            session.submit(request) { continuation.resume(returning: $0) }
        }
    }
    private func assertOracle(_ outcome: ProjectionOutcome, source: ProjectionSource, mode: SizeMode, hidden: Bool,
                              focus: String?, selection: String?, previous: ScanSnapshot? = nil, file: StaticString = #filePath, line: UInt = #line) throws {
        let oracle = try XCTUnwrap(FilterProjection(snapshot: source.snapshot, filter: outcome.filter, mode: mode,
            showHidden: hidden, focusPath: focus, selectionPath: selection, previous: previous,
            history: ["/r", "/r/a", "/missing"], historyIndex: 2, control: ScanControl()), file: file, line: line)
        let result = outcome.projection
        XCTAssertEqual(result.weights, oracle.weights, file: file, line: line)
        XCTAssertEqual(result.focus, oracle.focus, file: file, line: line)
        XCTAssertEqual(result.selection, oracle.selection, file: file, line: line)
        XCTAssertEqual(result.children, oracle.children, file: file, line: line)
        XCTAssertEqual(result.history, oracle.history, file: file, line: line)
        XCTAssertEqual(result.historyIndex, oracle.historyIndex, file: file, line: line)
        XCTAssertEqual(Array(result.snapshot.nodes), Array(oracle.snapshot.nodes), file: file, line: line)
        XCTAssertEqual(result.snapshot.tags, oracle.snapshot.tags, file: file, line: line)
    }
    @MainActor func testNavigationReuseMatchesFullOracleAcrossFiltersModesAndHiddenState() async throws {
        let source = ProjectionSource(fixture())
        for text in ["", "*.bin", "nomatch", ":red", "|\\a", "logicalsize>0b", "\\a;*.bin"] {
            for mode in [SizeMode.logical, .allocated] {
                for hidden in [true, false] {
                    let session = ProjectionSession(); defer { session.shutdown() }
                    let initial = await run(session, source: source, text: text, mode: mode, hidden: hidden)
                    XCTAssertFalse(initial.reusedEvaluation)
                    for focus in ["/r", "/r/a", "/gone", "/r/a"] {
                        let result = await run(session, source: source, text: text, mode: mode, hidden: hidden, focus: focus)
                        XCTAssertTrue(result.reusedEvaluation)
                        try assertOracle(result, source: source, mode: mode, hidden: hidden, focus: focus, selection: "/r/a/zero.bin")
                    }
                }
            }
        }
    }
    @MainActor func testZeroByteMembershipSurvivesCachedNavigation() async {
        let session = ProjectionSession(); defer { session.shutdown() }
        let source = ProjectionSource(fixture())
        _ = await run(session, source: source)
        let result = await run(session, source: source, focus: "/r")
        XCTAssertTrue(result.reusedEvaluation); XCTAssertEqual(result.projection.selection, 2)
        XCTAssertEqual(result.projection.weights[2], 0)
    }
    @MainActor func testNewSourceNeverReusesSameCountPathSnapshotOrTags() async throws {
        let session = ProjectionSession(); defer { session.shutdown() }
        let original = fixture(); let source = ProjectionSource(original)
        let frozen = await run(session, source: source, text: ":red")
        var changed = original; changed.nodes[3].logicalBytes = 99; changed.tags = ["/r/b.txt": 1]
        let current = ProjectionSource(changed)
        let result = await run(session, source: current, text: ":red", previous: original)
        XCTAssertFalse(result.reusedEvaluation)
        try assertOracle(result, source: current, mode: .logical, hidden: true, focus: "/r/a", selection: "/r/a/zero.bin", previous: original)
        XCTAssertEqual(frozen.projection.weights[0], 7)
        XCTAssertEqual(frozen.projection.snapshot.tags, original.tags)
        XCTAssertEqual(result.projection.weights[0], 11)
        let again = await run(session, source: current, text: ":red", focus: "/r")
        XCTAssertTrue(again.reusedEvaluation)
    }
    @MainActor func testKeyInvalidatesForModeHiddenFilterAndOnlyKeepsLatestEvaluation() async {
        let session = ProjectionSession(); defer { session.shutdown() }
        let source = ProjectionSource(fixture())
        _ = await run(session, source: source)
        let mode = await run(session, source: source, mode: .allocated)
        let hidden = await run(session, source: source, mode: .allocated, hidden: false)
        let filter = await run(session, source: source, text: "*.txt", mode: .allocated, hidden: false)
        let old = await run(session, source: source)
        for result in [mode, hidden, filter, old] { XCTAssertFalse(result.reusedEvaluation) }
    }
    @MainActor func testTimeConditionsAlwaysReevaluateAndInvalidFilterUsesAcceptedFallback() async throws {
        let session = ProjectionSession(); defer { session.shutdown() }
        let source = ProjectionSource(fixture())
        for text in [">1d", "create<5m", "accessed>1s"] {
            XCTAssertTrue(try ScanFilter(text).isTimeDependent)
            _ = await run(session, source: source, text: text)
            let repeated = await run(session, source: source, text: text)
            XCTAssertFalse(repeated.reusedEvaluation)
        }
        let accepted = await run(session, source: source)
        let invalid = await run(session, source: source, text: ":tag:invalid", fallback: accepted.filter)
        XCTAssertNotNil(invalid.error); XCTAssertTrue(invalid.reusedEvaluation)
        XCTAssertEqual(invalid.filter.text, accepted.filter.text)
        try assertOracle(invalid, source: source, mode: .logical, hidden: true, focus: "/r/a", selection: "/r/a/zero.bin")
    }
    @MainActor func testResetAndShutdownSuppressObsoletePublication() async {
        let session = ProjectionSession()
        let source = ProjectionSource(fixture())
        _ = await run(session, source: source)
        let stale = expectation(description: "reset request cannot publish"); stale.isInverted = true
        let request = ProjectionRequest(source: source, filterText: "*.bin", fallbackFilter: try! ScanFilter(""),
            mode: .logical, showHidden: true, focusPath: "/r", selectionPath: nil)
        session.submit(request) { _ in stale.fulfill() }
        session.reset()
        let next = await run(session, source: source)
        XCTAssertFalse(next.reusedEvaluation)
        session.shutdown()
        session.submit(request) { _ in stale.fulfill() }
        await fulfillment(of: [stale], timeout: 0.1)
    }
    @MainActor func testRemovedAndRenamedSourcesRepairHistoryLikeFullProjection() async throws {
        var original = fixture(); original.nodes[1].fileIdentity = "directory"; original.nodes[3].fileIdentity = "file"
        let session = ProjectionSession(); defer { session.shutdown() }
        _ = await run(session, source: ProjectionSource(original))
        var renamed = original
        renamed.nodes[1].path = "/r/renamed"; renamed.nodes[1].name = "renamed"
        renamed.nodes[2].path = "/r/renamed/zero.bin"; renamed.nodes[3].path = "/r/renamed/keep.bin"
        let source = ProjectionSource(renamed)
        let result = await run(session, source: source, selection: "/r/a/keep.bin", previous: original)
        XCTAssertFalse(result.reusedEvaluation)
        try assertOracle(result, source: source, mode: .logical, hidden: true, focus: "/r/a", selection: "/r/a/keep.bin", previous: original)
        XCTAssertEqual(result.projection.focus, 1); XCTAssertEqual(result.projection.selection, 3)
        let removed = ProjectionSource(ScanSnapshot(rootPath: "/r", nodes: [DiskNode(id: 0, parent: nil, path: "/r", name: "r", isDirectory: true)]))
        let gone = await run(session, source: removed, previous: renamed)
        try assertOracle(gone, source: removed, mode: .logical, hidden: true, focus: "/r/a", selection: "/r/a/zero.bin", previous: renamed)
        XCTAssertEqual(gone.projection.focus, 0); XCTAssertNil(gone.projection.selection)
    }
}
