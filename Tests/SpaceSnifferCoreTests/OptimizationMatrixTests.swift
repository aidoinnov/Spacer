import XCTest
import SnifferTestSupport
@testable import SpaceSnifferCore

final class OptimizationMatrixTests: XCTestCase, @unchecked Sendable {
    @MainActor private func run(_ session: ProjectionSession, _ source: ProjectionSource, filter: String = "", mode: SizeMode = .logical, hidden: Bool = true,
                                previous: ScanSnapshot? = nil, focus: String? = nil, selection: String? = nil) async -> ProjectionOutcome {
        let request = ProjectionRequest(source: source, filterText: filter, fallbackFilter: try! ScanFilter(""), mode: mode, showHidden: hidden,
            focusPath: focus ?? source.snapshot.rootPath, selectionPath: selection, previous: previous,
            history: [source.snapshot.rootPath, focus ?? source.snapshot.rootPath], historyIndex: 1)
        return await withCheckedContinuation { continuation in session.submit(request) { continuation.resume(returning: $0) } }
    }
    private func assertOracle(_ result: ProjectionOutcome, filter: String, mode: SizeMode, hidden: Bool, previous: ScanSnapshot? = nil,
                              focus: String? = nil, selection: String? = nil, file: StaticString = #filePath, line: UInt = #line) throws {
        let snapshot = result.projection.snapshot; let parsed = try ScanFilter(filter)
        let evaluation = try XCTUnwrap(ProjectionEvaluation(snapshot: snapshot, filter: parsed, mode: mode, showHidden: hidden, control: ScanControl()))
        XCTAssertEqual(result.projection.weights, evaluation.weights, file: file, line: line)
        let legacy = try XCTUnwrap(LegacyNavigationState(snapshot: snapshot, previous: previous, included: evaluation.included, weights: evaluation.weights,
            focusPath: focus ?? snapshot.rootPath, selectionPath: selection, history: [snapshot.rootPath, focus ?? snapshot.rootPath], historyIndex: 1, control: ScanControl()))
        XCTAssertEqual(result.projection.focus, legacy.focus, file: file, line: line)
        XCTAssertEqual(result.projection.selection, legacy.selection, file: file, line: line)
        XCTAssertEqual(result.projection.history, legacy.history, file: file, line: line)
        XCTAssertEqual(result.projection.historyIndex, legacy.historyIndex, file: file, line: line)
    }
    func testFixtureShapesValidateAndCOWStorageProofRejectsEveryMutation() throws {
        for shape in OptimizationFixture.Shape.allCases { _ = try OptimizationFixture.metadata(files: 300, shape: shape).validated() }
        let original = OptimizationFixture.metadata(files: 4000)
        var copy = original; XCTAssertTrue(copy.nodes.sharesStorage(with: original.nodes))
        copy.tags = [original.rootPath: 2]; XCTAssertTrue(copy.nodes.sharesStorage(with: original.nodes))
        copy.nodes[1025].children.append(3999); XCTAssertFalse(copy.nodes.sharesStorage(with: original.nodes))
        XCTAssertTrue(original.nodes[1025].children.isEmpty)
        var changed = original; changed.nodes[1025].name = "changed"
        XCTAssertFalse(changed.nodes.sharesStorage(with: original.nodes))
        XCTAssertEqual(changed.nodes.differingNodeIDs(from: original.nodes, control: ScanControl()), [1025])
    }
    @MainActor func testTagDependencyAndPublicMetadataMatrix() async throws {
        let base = OptimizationFixture.metadata(files: 1200, shape: .edges)
        for text in ["", "*.bin", "|*.txt", "\\branch-0", ">1kb", ":red", "|:red", ":green", ":attr:hidden"] {
            for mode in SizeMode.allCases { for hidden in [true, false] {
                let session = ProjectionSession(); let original = await run(session, ProjectionSource(base), filter: text, mode: mode, hidden: hidden)
                var tagged = base; tagged.tags = [base.rootPath: 4]
                let current = await run(session, ProjectionSource(tagged), filter: text, mode: mode, hidden: hidden, previous: base)
                XCTAssertEqual(current.evaluationKind == .reused, !(try ScanFilter(text)).isTagDependent, text)
                XCTAssertEqual(current.projection.snapshot.tags, tagged.tags)
                XCTAssertEqual(original.projection.snapshot.tags, base.tags)
                try assertOracle(current, filter: text, mode: mode, hidden: hidden, previous: base)
                session.shutdown()
            } }
        }
    }
    @MainActor func testSparsePositiveNegativeBoundaryAndZeroDeltasAgainstFullPass() async throws {
        for text in ["", "*.bin", ">32kb", "\\branch-0;*.txt", ":red", ":attr:hidden"] {
            for mode in SizeMode.allCases { for hidden in [true, false] {
                let session = ProjectionSession(); var snapshot = OptimizationFixture.metadata(files: 20_000)
                let id = 15_101; let focus = snapshot.nodes[1].path
                var before = await run(session, ProjectionSource(snapshot), filter: text, mode: mode, hidden: hidden, focus: focus, selection: snapshot.nodes[id].path)
                let frozen = before.projection.weights
                for size: Int64 in [0, 1, 32768, 33000, 70000, 0] {
                    let frozenWeights = before.projection.weights.map { $0 }
                    let frozenNodes = Array(before.projection.snapshot.nodes)
                    let old = snapshot
                    snapshot.nodes[id].logicalBytes = size; snapshot.nodes[id].allocatedBytes = size == 0 ? 0 : ((size + 4095) / 4096) * 4096
                    snapshot.nodes[id].modified = snapshot.nodes[id].modified.addingTimeInterval(1)
                    OptimizationFixture.aggregate(&snapshot)
                    let next = await run(session, ProjectionSource(snapshot), filter: text, mode: mode, hidden: hidden, previous: old, focus: focus, selection: snapshot.nodes[id].path)
                    XCTAssertNotEqual(next.evaluationKind, .full, text)
                    try assertOracle(next, filter: text, mode: mode, hidden: hidden, previous: old, focus: focus, selection: snapshot.nodes[id].path)
                    XCTAssertEqual(before.projection.weights, frozenWeights)
                    XCTAssertEqual(Array(before.projection.snapshot.nodes), frozenNodes)
                    before = next
                }
                XCTAssertFalse(frozen.isEmpty); session.shutdown()
            } }
        }
    }
    func testDeltaProvenanceDenseFallbackAndOverflowSafeAggregation() throws {
        let original = OptimizationFixture.metadata(files: 20_000); let base = ProjectionSource(original)
        var sparse = original; sparse.nodes[15001].logicalBytes += 5; OptimizationFixture.aggregate(&sparse)
        let changed = ProjectionSource(sparse); let delta = try XCTUnwrap(ProjectionDelta(baseline: base, result: changed, control: ScanControl()))
        let filter = try ScanFilter(""); let evaluation = try XCTUnwrap(ProjectionEvaluation(snapshot: original, filter: filter, mode: .logical, showHidden: true, control: ScanControl()))
        XCTAssertNil(delta.apply(previous: evaluation, baseline: ProjectionSource(original), result: changed, filter: filter, mode: .logical, showHidden: true, control: ScanControl()))
        let stopped = ScanControl(); stopped.cancel()
        XCTAssertNil(delta.apply(previous: evaluation, baseline: base, result: changed, filter: filter, mode: .logical, showHidden: true, control: stopped))
        var dense = original
        for id in dense.nodes.indices where !dense.nodes[id].isDirectory { dense.nodes[id].logicalBytes += 1 }
        OptimizationFixture.aggregate(&dense)
        XCTAssertNil(ProjectionDelta(baseline: base, result: ProjectionSource(dense), control: ScanControl()))
        let maximum = Int64.max
        let old = ScanSnapshot(rootPath: "/r", nodes: [DiskNode(id: 0, parent: nil, path: "/r", name: "r", isDirectory: true, logicalBytes: maximum, children: [1,2]), DiskNode(id: 1, parent: 0, path: "/r/a", name: "a", logicalBytes: maximum-10), DiskNode(id: 2, parent: 0, path: "/r/b", name: "b", logicalBytes: 10)])
        var new = old; new.nodes[1].logicalBytes = 10; new.nodes[2].logicalBytes = maximum-10
        let lhs = ProjectionSource(old); let rhs = ProjectionSource(new)
        let value = try XCTUnwrap(ProjectionEvaluation(snapshot: old, filter: filter, mode: .logical, showHidden: true, control: ScanControl()))
        let proof = try XCTUnwrap(ProjectionDelta(baseline: lhs, result: rhs, control: ScanControl()))
        let result = try XCTUnwrap(proof.apply(previous: value, baseline: lhs, result: rhs, filter: filter, mode: .logical, showHidden: true, control: ScanControl()))
        XCTAssertEqual(result.weights, [maximum,10,maximum-10]); XCTAssertEqual(value.weights, [maximum,maximum-10,10])
    }
    @MainActor func testUnknownMetadataTopologyAndTimeAlwaysFallBack() async throws {
        let base = OptimizationFixture.metadata(files: 1000)
        var variants: [ScanSnapshot] = []
        var value = base; value.nodes[500].name = "renamed.bin"; value.nodes[500].path = base.nodes[value.nodes[500].parent!].path + "/renamed.bin"; variants.append(value)
        value = base; value.nodes[1].nativeAttributes = 2; variants.append(value)
        value = base; value.nodes[500].nativeFlags = 0x10; variants.append(value)
        value = base; value.nodes[500].fileIdentity = "replacement"; variants.append(value)
        value = base; value.nodes[500].created = .now; variants.append(value)
        value = base; value.nodes[500].issue = "denied"; variants.append(value)
        value = base; value.nodes[0].children.reverse(); variants.append(value)
        for changed in variants {
            let session = ProjectionSession(); _ = await run(session, ProjectionSource(base))
            let result = await run(session, ProjectionSource(changed), previous: base)
            XCTAssertEqual(result.evaluationKind, .full); try assertOracle(result, filter: "", mode: .logical, hidden: true, previous: base); session.shutdown()
        }
        let session = ProjectionSession(); defer { session.shutdown() }
        let source = ProjectionSource(base)
        for _ in 0..<3 { let result = await run(session, source, filter: ">1d"); XCTAssertEqual(result.evaluationKind, .full) }
    }
    func testGeometryMatchesPreservedDoubleComparatorAndEveryLayoutInput() throws {
        let session = GeometrySession()
        for shape in [OptimizationFixture.Shape.edges, .wide, .deep] {
            let snapshot = OptimizationFixture.metadata(files: 600, shape: shape)
            var weights = try ScanFilter("").weights(in: snapshot, mode: .logical)
            if shape == .wide { weights[1] = 9_007_199_254_740_993; weights[2] = 9_007_199_254_740_992 }
            let source = GeometrySource(snapshot: snapshot, weights: weights)
            for root in [0, 1] { for depth in [1,3,6] { for selection: Int? in [nil, 2, snapshot.nodes.count-1] {
                for size in [CGSize(width: 320, height: 200), CGSize(width: 1400, height: 900), CGSize(width: 2, height: 2)] {
                    let bounds = CGRect(origin: .zero, size: size)
                    let expected = try XCTUnwrap(LegacyTreemap.tiles(snapshot: snapshot, weights: weights, root: root, depth: depth, selected: selection, in: bounds, control: ScanControl()))
                    let actual = try XCTUnwrap(session.tiles(source: source, root: root, depth: depth, selected: selection, in: bounds, control: ScanControl()))
                    XCTAssertEqual(actual.map(\.id), expected.map(\.id)); XCTAssertEqual(actual.map(\.rect), expected.map(\.rect)); XCTAssertEqual(actual.map(\.expanded), expected.map(\.expanded)); XCTAssertEqual(actual.map(\.level), expected.map(\.level))
                }
            } } }
        }
        XCTAssertLessThanOrEqual(session.statistics().retainedSortItems, 65536); XCTAssertLessThanOrEqual(session.statistics().retainedTiles, 50000)
        session.reset(); XCTAssertEqual(session.statistics().retainedSortItems, 0); XCTAssertEqual(session.statistics().retainedTiles, 0)
    }
    func testGeometryCacheHitsNeverRetainSourceAndCancelledWorkCannotPublish() throws {
        let snapshot = OptimizationFixture.metadata(files: 2000, shape: .wide); let weights = try ScanFilter("").weights(in: snapshot, mode: .logical)
        let session = GeometrySession(); var source: GeometrySource? = GeometrySource(snapshot: snapshot, weights: weights); weak let weakSource = source
        for width in [1000.0,1100.0,1000.0] { _ = session.tiles(source: source!, root: 0, depth: 2, selected: nil, in: CGRect(x: 0, y: 0, width: width, height: 600), control: ScanControl()) }
        XCTAssertGreaterThan(session.statistics().sortHits, 0); XCTAssertGreaterThan(session.statistics().rectHits, 0)
        let stopped = ScanControl(); stopped.cancel()
        XCTAssertNil(session.tiles(source: source!, root: 0, depth: 2, selected: nil, in: .zero, control: stopped))
        source = nil; XCTAssertNil(weakSource); session.reset()
    }
    func testTelemetrySeparatesEventsAndBoundsNamesSamplesAndThreads() {
        let telemetry = WorkerTelemetry(stageLimit: 8, sampleLimit: 16)
        telemetry.note("test", submitted: 3, coalesced: 1)
        telemetry.record("test"); let start = telemetry.begin("test", queuedAt: DispatchTime.now().uptimeNanoseconds)
        telemetry.end("test", since: start); telemetry.note("test", cancelled: 1, stale: 1)
        let sample = telemetry.snapshot()["test"]!
        XCTAssertEqual(sample.submitted, 3); XCTAssertEqual(sample.started, 1); XCTAssertEqual(sample.completed, 1); XCTAssertEqual(sample.cancelled, 1)
        XCTAssertEqual(sample.active, 0); XCTAssertEqual(sample.peakActive, 1); XCTAssertEqual(sample.queueSamples, 1)
        for _ in 0..<100 { telemetry.observe("test", nanoseconds: 5) }
        for id in 0..<100 { telemetry.record("stage-\(id)") }
        telemetry.record("/private/user-file")
        XCTAssertLessThanOrEqual(telemetry.snapshot().count, 8)
        XCTAssertEqual(telemetry.snapshot()["test"]!.recentNanoseconds.count, 16)
        XCTAssertNil(telemetry.snapshot()["/private/user-file"])
    }
    func testTelemetrySnapshotsRemainFrozenDuringConcurrentSampleUpdates() {
        let telemetry = WorkerTelemetry(stageLimit: 8, sampleLimit: 16)
        for i in 0..<16 { telemetry.observe("frozen", nanoseconds: UInt64(i)) }
        let frozen = telemetry.snapshot()
        DispatchQueue.concurrentPerform(iterations: 4) { index in
            for value in 0..<1000 { telemetry.observe("frozen", nanoseconds: UInt64(100 + index*1000 + value)) }
        }
        let current = telemetry.snapshot()["frozen"]!
        XCTAssertEqual(frozen["frozen"]!.recentNanoseconds, Array(0..<16).map(UInt64.init))
        XCTAssertEqual(frozen["frozen"]!.timedCalls, 16)
        XCTAssertEqual(current.timedCalls, 4016); XCTAssertEqual(current.recentNanoseconds.count, 16)
        XCTAssertTrue(current.recentNanoseconds.allSatisfy { $0 >= 100 })
    }
}
