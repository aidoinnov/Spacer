import XCTest
import Darwin
@testable import SpaceSnifferCore

final class ConfiguredExportIntegrationTests: XCTestCase, @unchecked Sendable {
    private func fixture() -> ScanSnapshot {
        ScanSnapshot(rootPath: "/r", nodes: [
            DiskNode(id: 0, parent: nil, path: "/r", name: "r", isDirectory: true, logicalBytes: 3, allocatedBytes: 3, children: [1]),
            DiskNode(id: 1, parent: 0, path: "/r/한.txt", name: "한.txt", logicalBytes: 3, allocatedBytes: 3)])
    }
    private func directory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("configured-export-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true); return url
    }
    func testInspectionRequiresExplicitFullConfigIndexButStandaloneSelectsZero() throws {
        let preset = NativeConfiguration.ExportConfiguration.simpleFileList
        let standalone = try ConfigurationFile.inspect(preset.encodedXML())
        XCTAssertNil(standalone.configuration); XCTAssertEqual(try standalone.selectingExport(), preset)
        let full = try ConfigurationFile.inspect(NativeConfiguration(exportConfigurations: [preset]).encodedXML())
        XCTAssertThrowsError(try full.selectingExport()) { XCTAssertEqual($0 as? ConfigurationFile.FileError, .exportIndexRequired) }
        XCTAssertEqual(try full.selectingExport(0), preset)
        XCTAssertThrowsError(try full.selectingExport(1))
        XCTAssertThrowsError(try ConfigurationFile.inspect(Data("<unrecognized/>".utf8)))
        XCTAssertThrowsError(try ConfigurationFile.inspect(Data("<!DOCTYPE exportConfig [<!ENTITY x SYSTEM 'file:///no-read'>]><exportConfig>&x;</exportConfig>".utf8)))
    }
    func testBoundedFileReadAndCancellation() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("config.xml")
        try Data(repeating: 32, count: 4_194_305).write(to: file)
        XCTAssertThrowsError(try ConfigurationFile.inspect(file)) { XCTAssertEqual($0 as? ConfigurationFile.FileError, .inputLimit) }
        let control = ScanControl(); control.cancel()
        XCTAssertThrowsError(try ConfigurationFile.inspect(file, control: control)) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertThrowsError(try ConfigurationFile.inspect(dir)) { XCTAssertEqual($0 as? ConfigurationFile.FileError, .notRegularFile) }
        let fifo = dir.appendingPathComponent("never-wait-for-writer")
        XCTAssertEqual(mkfifo(fifo.path, 0o600), 0)
        XCTAssertThrowsError(try ConfigurationFile.inspect(fifo)) { XCTAssertEqual($0 as? ConfigurationFile.FileError, .notRegularFile) }
    }
    func testWorkerInspectsExplicitFileWithoutApplyingConfiguration() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("export.xml")
        try NativeConfiguration.ExportConfiguration.simpleFileList.encodedXML().write(to: file)
        let worker = ArtifactWorker()
        let result = try await worker.inspectConfiguration(file)
        XCTAssertEqual(try result.selectingExport(), .simpleFileList)
        let cancelled = ScanControl(); cancelled.cancel()
        do { _ = try await worker.inspectConfiguration(file, control: cancelled); XCTFail("cancelled read") } catch { XCTAssertTrue(error is CancellationError) }
    }
    func testStreamingSuccessAndFailedBudgetNeverReplacesDestinationOrLeavesStaging() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("report.txt"), old = Data("PREVIOUS".utf8)
        try old.write(to: file)
        let source = fixture(), filter = try ScanFilter("")
        let tiny = ConfiguredExportOptions(configuration: .simpleFileList, filter: filter, maximumOutputBytes: 1)
        XCTAssertThrowsError(try ArtifactTransfer.exportConfigured(source, options: tiny, to: file))
        XCTAssertEqual(try Data(contentsOf: file), old)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["report.txt"])
        let normal = ConfiguredExportOptions(configuration: .simpleFileList, filter: filter)
        let result = try ArtifactTransfer.exportConfigured(source, options: normal, to: file)
        XCTAssertEqual(try Data(contentsOf: file), Data("/r/한.txt\n".utf8)); XCTAssertEqual(result.files, 1)
        XCTAssertThrowsError(try ArtifactTransfer.exportConfigured(source, options: normal, to: file, replaceExisting: false))
        XCTAssertEqual(try Data(contentsOf: file), Data("/r/한.txt\n".utf8))
    }
    func testCancellationDuringFinalFlushPreventsAtomicPublish() throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("report.txt"), old = Data("PREVIOUS".utf8)
        try old.write(to: file)
        let control = ScanControl()
        let actualIO = CancelOnWrite(control: control)
        let options = ConfiguredExportOptions(configuration: .simpleFileList, filter: try ScanFilter(""), control: control)
        XCTAssertThrowsError(try ArtifactTransfer.exportConfigured(fixture(), options: options, to: file, replaceExisting: true, io: actualIO)) { XCTAssertTrue($0 is CancellationError) }
        XCTAssertEqual(try Data(contentsOf: file), old)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: dir.path), ["report.txt"])
    }
    func testCancelledQueuedAsyncExportReleasesWithoutPublishing() async throws {
        let dir = try directory(); defer { try? FileManager.default.removeItem(at: dir) }
        let file = dir.appendingPathComponent("report.txt")
        let executor = ArtifactIOExecutor(), worker = ArtifactWorker(executor: executor)
        let started = expectation(description: "blocked queue"), gate = DispatchSemaphore(value: 0)
        defer { gate.signal() }
        let blocker = Task { try await executor.run { started.fulfill(); gate.wait() } }
        await fulfillment(of: [started], timeout: 3)
        let source = fixture(), options = ConfiguredExportOptions(configuration: .simpleFileList, filter: try ScanFilter(""))
        let job = Task { try await worker.exportConfigured(source, options: options, to: file) }
        for _ in 0..<3000 { if executor.outstandingCount == 2 { break }; try await Task.sleep(for: .milliseconds(1)) }
        XCTAssertEqual(executor.outstandingCount, 2)
        job.cancel(); gate.signal(); try await blocker.value
        do { _ = try await job.value; XCTFail("cancelled export must fail") } catch { XCTAssertTrue(error is CancellationError) }
        XCTAssertFalse(FileManager.default.fileExists(atPath: file.path)); XCTAssertEqual(executor.outstandingCount, 0)
    }
    func testExplicitMacDateFormattingIsDeterministicForFrozenLocaleZoneAndClock() throws {
        let formatting = MacExportFormatting.localized(locale: Locale(identifier: "en_US_POSIX"), timeZone: TimeZone(secondsFromGMT: 0)!)
        let format = try XCTUnwrap(formatting.time), date = Date(timeIntervalSince1970: 0)
        XCTAssertEqual(try format(date, .created, .date, date), "1/1/70")
        XCTAssertEqual(try format(nil, .created, .time, date), "*VOID*")
        XCTAssertEqual(try format(date, .modified, .age, date.addingTimeInterval(3600)), "1 hour ago")
    }
}
private struct CancelOnWrite: ArtifactFileIO {
    let control: ScanControl
    func write(_ descriptor: Int32, bytes: UnsafeRawBufferPointer) throws -> Int {
        let count = try NativeArtifactFileIO().write(descriptor, bytes: bytes); control.cancel(); return count
    }
    func close(_ descriptor: Int32) throws { try NativeArtifactFileIO().close(descriptor) }
    func publish(_ temporary: String, to destination: String, replaceExisting: Bool) throws { try NativeArtifactFileIO().publish(temporary, to: destination, replaceExisting: replaceExisting) }
}
