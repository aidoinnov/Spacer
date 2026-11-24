import XCTest
import SpaceSnifferCore
@testable import MacSpaceSniffer

@MainActor final class RescanNavigationTests: XCTestCase {
    private enum Failure: Error { case timeout }
    private func eventually(_ condition: () -> Bool) async throws {
        for _ in 0..<500 { if condition() { return }; try await Task.sleep(for: .milliseconds(10)) }
        throw Failure.timeout
    }
    func testIncompleteRescanDoesNotDeleteNavigationAndTerminalDeletionDoes() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("rescan-navigation-" + UUID().uuidString).resolvingSymlinksInPath()
        let nested = root.appendingPathComponent("a/nested")
        try FileManager.default.createDirectory(at: nested, withIntermediateDirectories: true)
        try Data([1, 2, 3]).write(to: nested.appendingPathComponent("keep.bin"))
        try Data([4]).write(to: root.appendingPathComponent("a/sibling.bin"))
        defer { try? FileManager.default.removeItem(at: root) }
        let firstGate = DispatchSemaphore(value: 0), secondGate = DispatchSemaphore(value: 0), replacementGate = DispatchSemaphore(value: 0)
        defer { firstGate.signal(); secondGate.signal(); replacementGate.signal() }
        let first = expectation(description: "rescan root-only partial"), second = expectation(description: "deletion root-only partial")
        let replacement = expectation(description: "new root initial partial")
        let calls = RescanCalls(); let admission = ScanAdmission(limit: 1); defer { admission.shutdown() }
        let service = ScanService(admission: admission, scanner: { url, control, progress, heartbeat in
            let number = calls.increment()
            return DiskScanner.scan(url, control: control, progress: { value in
                progress?(value)
                if value.nodes.count == 1 && number == 2 { first.fulfill(); _ = firstGate.wait(timeout: .now()+8) }
                if value.nodes.count == 1 && number == 3 { second.fulfill(); _ = secondGate.wait(timeout: .now()+8) }
                if value.nodes.count == 1 && number == 5 { replacement.fulfill(); _ = replacementGate.wait(timeout: .now()+8) }
            }, heartbeat: heartbeat)
        })
        let store = ScanStore(scanService: service); defer { store.shutdown() }
        store.liveUpdates = false; store.start(root)
        try await eventually { !store.isScanning && !store.projectionPending && store.snapshot?.fileCount == 2 }
        let complete = try XCTUnwrap(store.snapshot)
        let parentID = try XCTUnwrap(SnapshotTree.nodeID(at: root.appendingPathComponent("a").path, in: complete))
        let nestedID = try XCTUnwrap(SnapshotTree.nodeID(at: nested.path, in: complete))
        let fileID = try XCTUnwrap(SnapshotTree.nodeID(at: nested.appendingPathComponent("keep.bin").path, in: complete))
        store.navigate(parentID); try await eventually { !store.projectionPending }
        store.navigate(nestedID); try await eventually { !store.projectionPending }
        store.selected = fileID
        let history = store.history
        store.rescan(); await fulfillment(of: [first], timeout: 3)
        try await eventually { store.isScanning && store.scanProgress?.folderCount == 1 && !store.projectionPending }
        XCTAssertEqual(store.focusedNode?.path, nested.path); XCTAssertEqual(store.selectedNode?.path, nested.appendingPathComponent("keep.bin").path)
        XCTAssertEqual(store.history, history); XCTAssertEqual(store.snapshot?.fileCount, 2)
        // Authoritative tag updates must survive later partial callbacks, even
        // though the old complete presentation is held during the rescan.
        store.tag(nestedID, color: 1); try await eventually { !store.projectionPending && store.effectiveTag(nestedID) == 1 }
        store.tag(nestedID, color: 1); try await eventually { !store.projectionPending && store.effectiveTag(nestedID) == 0 }
        firstGate.signal()
        try await eventually { !store.isScanning && !store.projectionPending }
        XCTAssertEqual(store.focusedNode?.path, nested.path); XCTAssertEqual(store.history, history)
        XCTAssertEqual(store.effectiveTag(nestedID), 0)
        try FileManager.default.removeItem(at: nested)
        store.rescan(); await fulfillment(of: [second], timeout: 3)
        try await eventually { store.isScanning && store.scanProgress?.folderCount == 1 && !store.projectionPending }
        XCTAssertEqual(store.focusedNode?.path, nested.path); XCTAssertEqual(store.history, history)
        secondGate.signal()
        try await eventually { !store.isScanning && !store.projectionPending && store.snapshot?.fileCount == 1 }
        XCTAssertEqual(store.focusedNode?.path, root.appendingPathComponent("a").path)
        XCTAssertNil(store.selectedNode); XCTAssertEqual(store.history, [root.path, root.appendingPathComponent("a").path])
        // The terminal disappearance of the entire root is authoritative. It
        // must clear the complete marker and all now-unresolvable navigation.
        try FileManager.default.removeItem(at: root)
        store.rescan()
        try await eventually { !store.isScanning && !store.projectionPending && store.snapshot?.nodes.isEmpty == true }
        XCTAssertNil(store.focusedNode); XCTAssertNil(store.selectedNode)
        XCTAssertEqual(store.history, []); XCTAssertEqual(store.historyIndex, -1); XCTAssertNotNil(store.notice)
        let other = root.deletingLastPathComponent().appendingPathComponent("replacement-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: other, withIntermediateDirectories: true)
        try Data([1]).write(to: other.appendingPathComponent("new.bin"))
        defer { try? FileManager.default.removeItem(at: other) }
        store.start(other); await fulfillment(of: [replacement], timeout: 3)
        try await eventually { store.isScanning && !store.projectionPending && store.snapshot?.rootPath == other.path && store.snapshot?.nodes.count == 1 }
        XCTAssertEqual(store.history, [other.path]); XCTAssertEqual(store.snapshot?.fileCount, 0)
        replacementGate.signal()
        try await eventually { !store.isScanning && !store.projectionPending && store.snapshot?.fileCount == 1 }
        XCTAssertEqual(store.focusedNode?.path, other.path)
        store.shutdown()
        for _ in 0..<300 { if await service.statistics().roots == 0 { break }; try await Task.sleep(for: .milliseconds(10)) }
        let final = await service.statistics(); XCTAssertEqual(final.roots, 0)
    }
}

private final class RescanCalls: @unchecked Sendable {
    private let lock = NSLock(); private var count = 0
    func increment() -> Int { lock.withLock { count += 1; return count } }
}
