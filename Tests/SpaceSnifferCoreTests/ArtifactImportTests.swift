import XCTest
@testable import SpaceSnifferCore

final class ArtifactImportTests: XCTestCase, @unchecked Sendable {
    func testDUDispatchMetadataAndExplicitRootSelection() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("input.DU")
        try Data("10 C:\\alpha\r\n4 C:\\alpha\\child\r\n3 D:\\other\r\n".utf8).write(to: url)
        let roots = try ArtifactTransfer.inspectRoots(url)
        XCTAssertEqual(roots.map(\.path), ["C:\\", "D:\\"])
        XCTAssertEqual(roots.map(\.allocatedBytes), [10240, 3072])
        XCTAssertThrowsError(try ArtifactTransfer.load(url)) {
            XCTAssertEqual($0 as? DUSnapshot.FormatError, .rootSelectionRequired(2))
        }
        let selected = try ArtifactTransfer.load(url, rootIndex: 1)
        XCTAssertEqual(selected.rootPath, "D:\\")
        XCTAssertEqual(selected.fileCount, 0) // Missing aggregate is not a real file count.
        XCTAssertEqual(try ScanFilter("").weights(in: selected, mode: .allocated)[0], 3072)
    }
    func testCancelledImportIsRejectedBeforeOpeningFile() throws {
        let control = ScanControl(); control.cancel()
        let missing = URL(fileURLWithPath: "/missing-" + UUID().uuidString + ".sns")
        XCTAssertThrowsError(try ArtifactTransfer.load(missing, control: control)) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertThrowsError(try ArtifactTransfer.inspectRoots(missing, control: control)) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertThrowsError(try SNSSnapshot.decode(Data(), control: control)) { XCTAssertTrue($0 is CancellationError) }
    }
    func testQueuedTaskCancellationPreventsImportAfterIOQueueDrains() async throws {
        let executor = ArtifactIOExecutor()
        let queuedWorker = ArtifactWorker(executor: executor)
        let gate = DispatchSemaphore(value: 0); defer { gate.signal() }
        let started = expectation(description: "I/O blocked")
        let blocker = Task { try await executor.run { started.fulfill(); gate.wait() } }
        await fulfillment(of: [started], timeout: 3)
        let load = Task { try await queuedWorker.load(URL(fileURLWithPath: "/missing-" + UUID().uuidString + ".sns")) }
        for _ in 0..<1000 {
            if executor.outstandingCount == 2 { break }
            try await Task.sleep(for: .milliseconds(1))
        }
        XCTAssertEqual(executor.outstandingCount, 2)
        load.cancel(); gate.signal(); try await blocker.value
        do { _ = try await load.value; XCTFail("Cancelled queue item must not read") }
        catch { XCTAssertTrue(error is CancellationError, "\(error)") }
        XCTAssertEqual(executor.outstandingCount, 0)
    }
    func testWindowsPathDetectionPreservesGraphemeSemanticsWithoutCountingWholePath() {
        let cases = ["", "a", ":", "C:", "C:\\folder", "/tmp", "\\\\host\\share", "é:folder", "e\u{301}:folder", "👨‍👩‍👦:folder", "/" + String(repeating: "한글/", count: 1000)]
        for path in cases {
            let old = path.hasPrefix("\\\\") || path.count >= 2 && path[path.index(after: path.startIndex)] == ":"
            XCTAssertEqual(SnapshotPath.isWindows(path), old, path)
        }
    }
}
