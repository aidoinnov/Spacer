import XCTest
import Darwin
@testable import SpaceSnifferCore

final class DirectoryWatchPathTests: XCTestCase, @unchecked Sendable {
    func testRootMappingDoesNotConsultRemovedItemOrCrossSiblingBoundary() {
        let mapping = DirectoryWatchPath(root: "/tmp/root", nativeRoot: "/private/tmp/root")
        XCTAssertEqual(mapping.map("/private/tmp/root"), "/tmp/root")
        XCTAssertEqual(mapping.map("/private/tmp/root/gone/removed.bin"), "/tmp/root/gone/removed.bin")
        XCTAssertEqual(mapping.map("/private/tmp/root-other/a"), "/private/tmp/root-other/a")
        XCTAssertEqual(mapping.map("/outside/a"), "/outside/a")
        XCTAssertEqual(DirectoryWatchPath(root: "/", nativeRoot: "/").map("/a"), "/a")
        XCTAssertEqual(DirectoryWatchPath(root: "/visible", nativeRoot: "/").map("/a"), "/visible/a")
    }

    func testFoundationPrivateAliasDeletionStillMapsIntoCachedRoot() throws {
        let input = "/private/tmp/watch-alias-" + UUID().uuidString
        let url = URL(fileURLWithPath: input)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: url) }
        let leaf = input + "/removed.bin"
        try Data([1]).write(to: URL(fileURLWithPath: leaf))
        let root = url.standardizedFileURL.resolvingSymlinksInPath().path
        let existing = URL(fileURLWithPath: leaf).standardizedFileURL.path
        try FileManager.default.removeItem(atPath: leaf)
        let removed = URL(fileURLWithPath: leaf).standardizedFileURL.path
        let mapping = DirectoryWatchPath(root: root, nativeRoot: input)
        XCTAssertEqual(URL(fileURLWithPath: mapping.map(leaf)).standardizedFileURL.path, existing)
        XCTAssertTrue(SnapshotTree.contains(root, mapping.map(removed)))
    }

    func testNativeWatchRepeatedRenameAndDeleteConvergesToFullScan() async throws {
        let root = URL(fileURLWithPath: "/private/tmp/watch-repeat-" + UUID().uuidString).resolvingSymlinksInPath()
        for i in 0..<48 {
            try FileManager.default.createDirectory(at: root.appendingPathComponent("branch-\(i)"), withIntermediateDirectories: true)
        }
        defer { try? FileManager.default.removeItem(at: root) }
        let service = ScanService()
        let subscription = await service.subscribe(root, watching: true)
        let initial = DiskScanner.scan(root)
        do {
            _ = try await settled(subscription, matching: initial)
            for round in 0..<5 {
                for i in 0..<48 {
                    let from = root.appendingPathComponent("branch-\(i)/event.bin")
                    let to = root.appendingPathComponent("branch-\(i)/renamed.bin")
                    try Data(repeating: UInt8(i), count: (round % 7 + 1) * (i + 1)).write(to: from)
                    XCTAssertEqual(rename(from.path, to.path), 0)
                    if (i + round) % 3 == 0 { XCTAssertEqual(unlink(to.path), 0) }
                }
                let oracle = DiskScanner.scan(root)
                let observed = try await settled(subscription, matching: oracle)
                XCTAssertTrue(observed.watchActive)
                _ = try observed.snapshot.validated()
                XCTAssertEqual(Set(observed.snapshot.nodes.map(\.path)), Set(oracle.nodes.map(\.path)))
                for node in oracle.nodes {
                    let id = try XCTUnwrap(SnapshotTree.nodeID(at: node.path, in: observed.snapshot))
                    XCTAssertEqual(observed.snapshot.nodes[id].logicalBytes, node.logicalBytes)
                    XCTAssertEqual(observed.snapshot.nodes[id].allocatedBytes, node.allocatedBytes)
                    XCTAssertEqual(observed.snapshot.nodes[id].fileIdentity, node.fileIdentity)
                }
            }
        } catch {
            await service.unsubscribe(subscription.id, rootPath: subscription.rootPath)
            throw error
        }
        await service.unsubscribe(subscription.id, rootPath: subscription.rootPath)
        let stats = await service.statistics()
        XCTAssertEqual(stats.roots, 0)
    }

    private func settled(_ subscription: ScanSubscription, matching oracle: ScanSnapshot) async throws -> ScanUpdate {
        try await withThrowingTaskGroup(of: ScanUpdate.self) { group in
            group.addTask {
                for await value in subscription.updates where !value.isScanning && !value.snapshot.cancelled {
                    if value.snapshot.fileCount == oracle.fileCount,
                       value.snapshot.nodes.first?.logicalBytes == oracle.nodes.first?.logicalBytes,
                       value.snapshot.nodes.first?.allocatedBytes == oracle.nodes.first?.allocatedBytes {
                        return value
                    }
                }
                throw CancellationError()
            }
            group.addTask { try await Task.sleep(for: .seconds(20)); throw CancellationError() }
            defer { group.cancelAll() }
            return try await group.next()!
        }
    }
}
