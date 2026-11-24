import AppKit
import XCTest
import SnifferTestSupport
import SpaceSnifferAutomation
@testable import SpaceSnifferCore
@testable import MacSpaceSniffer

@MainActor final class FrozenPresentationReadersTests: XCTestCase {
    func testTransitionQueryExportAndRunningBaselineSurviveRenameCancellationAndUnsubscribe() async throws {
        let input = OptimizationFixture.metadata(files: 2000)
        let filter = try ScanFilter(""); let weights = filter.weights(in: input, mode: .logical)
        let query = QueryContext(snapshot: input, weights: weights, filter: filter, mode: .logical, showHidden: true, revision: "frozen", focus: 0, selection: nil)
        let expected = try SNSSnapshot.encode(input); let id = try XCTUnwrap(input.nodes.first(where: { !$0.isDirectory })?.id)
        func item(_ x: Int) -> MapItem {
            MapItem(tile: TreemapTile(id: id, rect: CGRect(x: x, y: 0, width: 100, height: 100), expanded: false, level: 1), node: input.nodes[id],
                parentPath: input.nodes[input.nodes[id].parent!].path, sizeText: formattedBytes(weights[id]), sizeWidth: 30, tag: 0, category: .other, displayBytes: weights[id])
        }
        let transition = MapTransition(from: [item(0)], to: [item(100)], at: 1)
        let transitionNodes = transition.items(at: 1.2).map(\.node)
        let scanGate = DispatchSemaphore(value: 0); let exportGate = DispatchSemaphore(value: 0)
        defer { scanGate.signal(); exportGate.signal() }
        let calls = FrozenOverlapCounter(); let admission = ScanAdmission(limit: 1, capacity: 4); defer { admission.shutdown() }
        let service = ScanService(admission: admission, scanner: { _, _, _, _ in
            if calls.increment() > 1 { _ = scanGate.wait(timeout: .now()+15) }
            return input
        })
        let lease = await service.subscribe(URL(fileURLWithPath: input.rootPath), watching: false)
        for await update in lease.updates where !update.isScanning && !update.snapshot.nodes.isEmpty { break }
        await service.rescan(rootPath: lease.rootPath)
        for _ in 0..<500 where calls.value < 2 { try await Task.sleep(for: .milliseconds(2)) }
        XCTAssertEqual(calls.value, 2); XCTAssertEqual(admission.statistics().active, 1)
        // The real ScanService refresh now owns its frozen baseline while native work waits.
        let io = ArtifactIOExecutor(capacity: 2, label: "test.frozen.export", stage: "test.frozen.export")
        let worker = ArtifactWorker(executor: io)
        let exportEntered = FrozenOverlapCounter()
        let blocker = Task { try await io.run { _ = exportEntered.increment(); _ = exportGate.wait(timeout: .now()+15); return 0 } }
        for _ in 0..<500 where exportEntered.value == 0 { try await Task.sleep(for: .milliseconds(2)) }
        XCTAssertEqual(exportEntered.value, 1)
        let output = FileManager.default.temporaryDirectory.appendingPathComponent("sniffer-frozen-" + UUID().uuidString + ".sns")
        defer { try? FileManager.default.removeItem(at: output) }
        let export = Task { try await worker.save(query.snapshot, to: output) }
        for _ in 0..<500 where io.outstandingCount < 2 { try await Task.sleep(for: .milliseconds(2)) }
        XCTAssertEqual(io.outstandingCount, 2)
        let start = FrozenOverlapGate()
        let reader = Task.detached {
            await start.wait()
            for _ in 0..<20 {
                _ = try query.query(command: "tree_children", arguments: ["limit": .int(2)])
                XCTAssertEqual(try SNSSnapshot.encode(query.snapshot), expected)
                try await Task.sleep(for: .milliseconds(1))
            }
            return query.weights
        }
        let writer = Task.detached {
            var next = input; let control = ScanControl()
            for pass in 0..<6 {
                next.nodes[id].name = "renamed-\(pass).bin"
                next.nodes[id].path = next.nodes[next.nodes[id].parent!].path + "/" + next.nodes[id].name
                next.nodes[id].logicalBytes += 7; OptimizationFixture.aggregate(&next)
                if pass == 0 { await start.open() }
                if pass == 3 { control.cancel() }
                let value = FilterProjection(snapshot: next, filter: filter, mode: .logical, showHidden: true,
                    focusPath: input.rootPath, selectionPath: nil, previous: input, control: control)
                if control.isCancelled { XCTAssertNil(value); break }
                XCTAssertNotNil(value); try await Task.sleep(for: .milliseconds(2))
            }
            return next
        }
        let changed = try await writer.value; XCTAssertNotEqual(changed.nodes[id], input.nodes[id])
        let frozenWeights = try await reader.value; XCTAssertEqual(frozenWeights, weights)
        XCTAssertEqual(transition.items(at: 1.2).map(\.node), transitionNodes)
        XCTAssertEqual(try SNSSnapshot.encode(query.snapshot), expected)
        await service.unsubscribe(lease.id, rootPath: lease.rootPath)
        let stats = await service.statistics(); XCTAssertEqual(stats.roots, 0)
        scanGate.signal(); exportGate.signal(); _ = try await blocker.value; try await export.value
        let loaded = try await worker.load(output); XCTAssertEqual(try SNSSnapshot.encode(loaded), expected)
        for _ in 0..<500 where admission.statistics().active > 0 { try await Task.sleep(for: .milliseconds(2)) }
        XCTAssertEqual(admission.statistics().active, 0); XCTAssertEqual(io.outstandingCount, 0)
        XCTAssertEqual(transition.items(at: 1.2).map(\.node), transitionNodes)
        print("FROZEN_OVERLAP transition=true query_iterations=20 queued_export=true running_baseline=true rename_cancel=true unsubscribed_roots=0")
    }
}
private final class FrozenOverlapCounter: @unchecked Sendable {
    private let lock = NSLock(); private var count = 0
    func increment() -> Int { lock.withLock { count += 1; return count } }
    var value: Int { lock.withLock { count } }
}
private actor FrozenOverlapGate {
    private var opened = false
    private var continuations: [CheckedContinuation<Void,Never>] = []
    func wait() async { if !opened { await withCheckedContinuation { continuations.append($0) } } }
    func open() { opened = true; for c in continuations { c.resume() }; continuations.removeAll() }
}
