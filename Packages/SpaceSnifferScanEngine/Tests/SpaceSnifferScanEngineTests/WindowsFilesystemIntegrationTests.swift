#if os(Windows)
import Foundation
import XCTest
@testable import SpaceSnifferScanEngine

/// Actual Windows filesystem I/O through Foundation, exercised by the same
/// production pool used on Mac. This is a validation adapter, not a production
/// Win32 batch reader, Windows GUI, allocated-byte or reparse-point backend.
final class WindowsFilesystemIntegrationTests: XCTestCase {
    private struct Entry: Sendable, Equatable {
        let name: String
        let directory: Bool
        let logicalBytes: UInt64
    }
    private enum Read: Sendable {
        case listing([Entry])
        case failure(Int)
        case cancelled
    }
    private struct Reader: DirectoryBatchReader {
        let onEntry: @Sendable (Int) -> Void
        init(onEntry: @escaping @Sendable (Int) -> Void = { _ in }) { self.onEntry = onEntry }
        func readDirectory(at path: String, control: ScanControl) -> Read {
            guard !control.isCancelled else { return .cancelled }
            do {
                let names = try FileManager.default.contentsOfDirectory(atPath: path).sorted {
                    $0.utf8.lexicographicallyPrecedes($1.utf8)
                }
                var entries: [Entry] = []
                for name in names {
                    guard !control.isCancelled else { return .cancelled }
                    let child = URL(fileURLWithPath: path).appendingPathComponent(name).path
                    let metadata = try FileManager.default.attributesOfItem(atPath: child)
                    let directory = metadata[.type] as? FileAttributeType == .typeDirectory
                    entries.append(Entry(name: name, directory: directory,
                        logicalBytes: directory ? 0 : (metadata[.size] as? NSNumber)?.uint64Value ?? 0))
                    onEntry(entries.count)
                }
                return control.isCancelled ? .cancelled : .listing(entries)
            } catch { return .failure((error as NSError).code) }
        }
    }
    private func fixture() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sniffer-win-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    private func entries(_ result: Read, file: StaticString = #filePath, line: UInt = #line) throws -> [Entry] {
        guard case .listing(let entries) = result else {
            XCTFail("Expected successful directory batch", file: file, line: line)
            throw CocoaError(.fileReadUnknown)
        }
        return entries
    }

    func testActualWindowsFilesMatchSerialAcrossOneTwoFourWorkers() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        var folders: [URL] = []; var expectedBytes: UInt64 = 0
        for branch in 0..<100 {
            let dir = root.appendingPathComponent(String(format: "branch-%03d", branch))
            try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            folders.append(dir)
            for i in 0..<96 {
                let bytes = 1 + i % 31
                try Data(repeating: UInt8(i), count: bytes).write(to: dir.appendingPathComponent("f\(i).bin"))
                expectedBytes += UInt64(bytes)
            }
        }
        // These names must survive byte-for-byte, including canonical-equivalent
        // spellings. NTFS names are never normalized by the shared pool.
        let names = ["한글-空白 name.bin", "café.bin", "cafe\u{301}.bin", "🙂.bin"]
        let unicode = root.appendingPathComponent("unicode"); try FileManager.default.createDirectory(at: unicode, withIntermediateDirectories: true)
        for name in names { try Data([1, 2, 3]).write(to: unicode.appendingPathComponent(name)); expectedBytes += 3 }
        folders.append(unicode)
        var deep = root
        for _ in 0..<12 { deep.appendPathComponent("deep"); try FileManager.default.createDirectory(at: deep, withIntermediateDirectories: true) }
        try Data([9]).write(to: deep.appendingPathComponent("leaf.bin")); expectedBytes += 1; folders.append(deep)
        let reader = Reader()
        let baseline = try folders.map { try entries(reader.readDirectory(at: $0.path, control: ScanControl())) }
        XCTAssertEqual(baseline.flatMap { $0 }.filter { !$0.directory }.count, 9605)
        XCTAssertEqual(baseline.flatMap { $0 }.reduce(UInt64(0)) { $0 + $1.logicalBytes }, expectedBytes)
        XCTAssertEqual(baseline[100].map { Array($0.name.utf8) }, names.sorted { $0.utf8.lexicographicallyPrecedes($1.utf8) }.map { Array($0.utf8) })
        for workers in [1, 2, 4] {
            let budget = DirectoryIOBudget(limit: 4)
            let pool = DirectoryWorkerPool<Read>(workers: workers, capacity: folders.count,
                budget: budget, cancelledOutput: { .cancelled })
            defer { pool.shutdown() }
            var tickets: [DirectoryReadTicket<Read>] = []
            for folder in folders {
                tickets.append(try XCTUnwrap(pool.submit(reader: reader, path: folder.path, control: ScanControl())))
            }
            for (index, ticket) in tickets.enumerated() {
                let observed = try entries(ticket.wait())
                XCTAssertEqual(observed, baseline[index])
                XCTAssertEqual(observed.map { Array($0.name.utf8) }, baseline[index].map { Array($0.name.utf8) })
            }
            pool.shutdown()
            XCTAssertTrue(pool.isTerminated)
            XCTAssertEqual(budget.observation.active, 0)
            XCTAssertLessThanOrEqual(budget.observation.peak, 4)
        }
        print("WINDOWS_FS files=9605 branches=100 deep=12 workers=1,2,4 logical_bytes=\(expectedBytes) exact=true")
    }

    func testActualWindowsRenameDeleteAndRescanReplaceOldListing() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        let old = root.appendingPathComponent("old.bin"), renamed = root.appendingPathComponent("새 이름.bin")
        try Data([1, 2, 3]).write(to: old)
        let reader = Reader(); let budget = DirectoryIOBudget(limit: 1)
        let pool = DirectoryWorkerPool<Read>(workers: 1, capacity: 1, budget: budget, cancelledOutput: { .cancelled })
        defer { pool.shutdown() }
        func read() throws -> [Entry] {
            let ticket = try XCTUnwrap(pool.submit(reader: reader, path: root.path, control: ScanControl()))
            return try entries(ticket.wait())
        }
        XCTAssertEqual(try read().map(\.name), ["old.bin"])
        try FileManager.default.moveItem(at: old, to: renamed)
        XCTAssertEqual(try read().map(\.name), ["새 이름.bin"])
        try Data([1, 2, 3, 4, 5]).write(to: renamed)
        XCTAssertEqual(try read().first?.logicalBytes, 5)
        try FileManager.default.removeItem(at: renamed)
        XCTAssertTrue(try read().isEmpty)
        XCTAssertEqual(budget.observation.active, 0)
    }

    func testActualWindowsReaderCancellationAndMissingDirectorySettle() throws {
        let root = try fixture(); defer { try? FileManager.default.removeItem(at: root) }
        for i in 0..<130 { try Data([1]).write(to: root.appendingPathComponent("f\(i).bin")) }
        let budget = DirectoryIOBudget(limit: 1)
        let pool = DirectoryWorkerPool<Read>(workers: 1, capacity: 2, budget: budget, cancelledOutput: { .cancelled })
        defer { pool.shutdown() }
        let control = ScanControl()
        let reader = Reader { index in if index == 1 { control.cancel() } }
        let ticket = try XCTUnwrap(pool.submit(reader: reader, path: root.path, control: control))
        guard case .cancelled = ticket.wait() else { return XCTFail("partial listing escaped cancellation") }
        XCTAssertEqual(budget.observation.active, 0)
        let missing = try XCTUnwrap(pool.submit(reader: Reader(), path: root.appendingPathComponent("missing").path, control: ScanControl()))
        guard case .failure = missing.wait() else { return XCTFail("missing directory reported as success") }
        let cancelled = ScanControl(); cancelled.cancel()
        let before = try XCTUnwrap(pool.submit(reader: Reader { _ in XCTFail("cancelled reader executed") }, path: root.path, control: cancelled))
        guard case .cancelled = before.wait() else { return XCTFail("pre-cancellation lost") }
        pool.shutdown(); XCTAssertTrue(pool.isTerminated); XCTAssertEqual(budget.observation.active, 0)
    }
}
#endif
