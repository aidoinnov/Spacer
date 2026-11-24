import Foundation
import XCTest
import WinSDK
import SpaceSnifferScanEngine
@testable import WindowsScanCore
final class WindowsScannerTests: XCTestCase {
    private func root() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("sniffer-native-" + UUID().uuidString)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
    func testNativeBatchWorkersAgreeWithKnownFileOracleAndUnicode() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        var bytes: UInt64 = 0
        for b in 0..<32 {
            let dir = root.appendingPathComponent("b\(b)");try FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
            for i in 0..<64 { let count = 1024+i;try Data(repeating: 1,count: count).write(to: dir.appendingPathComponent("f\(i)"));bytes += UInt64(count) }
        }
        let names = ["한글🙂", "café", "cafe\u{301}"]
        for name in names { try Data(repeating: 1,count: 1000).write(to: root.appendingPathComponent(name));bytes += 1000 }
        let one = WindowsScanner.scan(root: root.path, control: ScanControl(), workers: 1)
        let four = WindowsScanner.scan(root: root.path, control: ScanControl(), workers: 4)
        XCTAssertEqual(one.files,2051);XCTAssertEqual(four.files,2051);XCTAssertEqual(one.folders,33)
        XCTAssertEqual(one.nodes[0].logical,bytes);XCTAssertEqual(four.nodes[0].logical,bytes)
        XCTAssertEqual(one.nodes[0].allocated,four.nodes[0].allocated);XCTAssertGreaterThan(one.nodes[0].allocated,0)
        XCTAssertEqual(one.errors,0);XCTAssertEqual(four.errors,0)
        let a = one.nodes.sorted { $0.path.utf16.lexicographicallyPrecedes($1.path.utf16) }
        let b = four.nodes.sorted { $0.path.utf16.lexicographicallyPrecedes($1.path.utf16) }
        XCTAssertEqual(a.map { Array($0.path.utf16) }, b.map { Array($0.path.utf16) })
        XCTAssertEqual(a.map(\.logical),b.map(\.logical));XCTAssertEqual(a.map(\.allocated),b.map(\.allocated))
    }
    func testNativeHardLinksCountPhysicalAllocationOnce() throws {
        let root = try root();defer { try? FileManager.default.removeItem(at: root) }
        let first = root.appendingPathComponent("a"),second = root.appendingPathComponent("b")
        try Data(repeating: 1,count: 10000).write(to: first)
        let success = (Array(second.path.utf16)+[0]).withUnsafeBufferPointer { dst in
            (Array(first.path.utf16)+[0]).withUnsafeBufferPointer { src in CreateHardLinkW(dst.baseAddress,src.baseAddress,nil) }
        }
        XCTAssertTrue(success)
        let scan = WindowsScanner.scan(root: root.path, control: ScanControl())
        XCTAssertEqual(scan.files,2);XCTAssertEqual(scan.nodes[0].logical,20000);XCTAssertEqual(scan.errors,0)
        XCTAssertEqual(scan.nodes.dropFirst().filter { $0.allocated == 0 }.count,1)
        XCTAssertGreaterThan(scan.nodes[0].allocated,0)
    }
    func testNativeCancellationAndMissingFolderTerminate() throws {
        let root = try root();defer { try? FileManager.default.removeItem(at: root) }
        for i in 0..<50 { try FileManager.default.createDirectory(at: root.appendingPathComponent("b\(i)"),withIntermediateDirectories:true) }
        let before = ScanControl();before.cancel()
        XCTAssertTrue(WindowsScanner.scan(root:root.path,control:before).cancelled)
        let during = ScanControl()
        XCTAssertTrue(WindowsScanner.scan(root:root.path,control:during,progress:{ _ in during.cancel() }).cancelled)
        let absent = WindowsScanner.scan(root:root.appendingPathComponent("missing").path,control:ScanControl())
        XCTAssertEqual(absent.errors,1);XCTAssertNotNil(absent.nodes[0].error);XCTAssertEqual(absent.files,0)
    }
    func testOversizedWorkerBatchRetriesInlineWithoutLosingEntries() throws {
        let root = try root(); defer { try? FileManager.default.removeItem(at: root) }
        let folder = root.appendingPathComponent("large")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        for i in 0..<4097 { try Data([1]).write(to: folder.appendingPathComponent("f\(i)")) }
        let scan = WindowsScanner.scan(root: root.path, control: ScanControl())
        XCTAssertEqual(scan.files,4097);XCTAssertEqual(scan.folders,2);XCTAssertEqual(scan.nodes[0].logical,4097)
        XCTAssertEqual(scan.errors,0);XCTAssertFalse(scan.cancelled)
    }
    func testJunctionBoundaryIsVisibleButTargetIsNotTraversed() throws {
        let root = try root(), target = try self.root()
        defer { try? FileManager.default.removeItem(at: root); try? FileManager.default.removeItem(at: target) }
        try Data([1,2,3]).write(to: target.appendingPathComponent("outside.bin"))
        let process = Process();process.executableURL=URL(fileURLWithPath:"C:\\Windows\\System32\\cmd.exe")
        process.arguments=["/d","/c","mklink","/J",root.appendingPathComponent("junction").path.replacingOccurrences(of:"/",with:"\\"),target.path.replacingOccurrences(of:"/",with:"\\")]
        let stdout=Pipe(), stderr=Pipe();process.standardOutput=stdout;process.standardError=stderr;try process.run();process.waitUntilExit()
        print("JUNCTION_COMMAND root=\(root.path) target=\(target.path) out=\(String(decoding:stdout.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self)) err=\(String(decoding:stderr.fileHandleForReading.readDataToEndOfFile(),as:UTF8.self))")
        XCTAssertEqual(process.terminationStatus,0)
        let scan = WindowsScanner.scan(root:root.path,control:ScanControl())
        XCTAssertEqual(scan.excluded,1);XCTAssertEqual(scan.files,0);XCTAssertEqual(scan.folders,2)
        let all=WindowsScanner.scan(root:root.path,control:ScanControl(),includeMountedVolumes:true)
        XCTAssertEqual(all.files,0);XCTAssertEqual(all.excluded,1)
        XCTAssertEqual(scan.nodes.count,2);XCTAssertTrue(try XCTUnwrap(scan.nodes.dropFirst().first).boundary);XCTAssertEqual(scan.errors,0)
    }

    func testRootMetadataAndVolumeCapacityAreQueriedOnceAtScanRoot() throws {
        let root=try root();defer{try? FileManager.default.removeItem(at:root)}
        let scan=WindowsScanner.scan(root:root.path,control:ScanControl())
        XCTAssertGreaterThan(scan.nodes[0].createdTicks,0);XCTAssertGreaterThan(scan.nodes[0].modifiedTicks,0)
        XCTAssertGreaterThan(scan.volumeTotal,0);XCTAssertLessThanOrEqual(scan.volumeFree,scan.volumeTotal)
        XCTAssertFalse(scan.isVolumeRoot)
        let drive=String(root.path.replacingOccurrences(of:"/",with:"\\").prefix(3))
        let volume=WindowsVolumeIdentity.read(drive,exactMount:true)
        XCTAssertNotNil(volume)
        XCTAssertNil(WindowsVolumeIdentity.read(root.path,exactMount:true))
    }
    private struct MountedReader:DirectoryBatchReader {
        func readDirectory(at path:String,control:ScanControl)->Batch {
            if path == "C:\\scope" {
                return .listing([
                    NativeEntry(name:"a",directory:true,reparse:true,attributes:0x410,logical:0,allocated:0,identity:nil,mountedVolume:"other"),
                    NativeEntry(name:"b",directory:true,reparse:true,attributes:0x410,logical:0,allocated:0,identity:nil,mountedVolume:"other"),
                    NativeEntry(name:"cycle",directory:true,reparse:true,attributes:0x410,logical:0,allocated:0,identity:nil,mountedVolume:"root"),
                    NativeEntry(name:"junction",directory:true,reparse:true,attributes:0x410,logical:0,allocated:0,identity:nil)])
            }
            return .listing([NativeEntry(name:"file",directory:false,reparse:false,attributes:0,logical:7,allocated:4096,identity:nil)])
        }
    }
    func testMountedPolicyDeduplicatesVolumeAliasesAndRejectsCyclesAndJunctions() {
        let reader=MountedReader()
        let selected=WindowsTreeBuilder.scan(root:"C:\\scope",control:ScanControl(),policy:WindowsScanPolicy(workers:4),boundedReader:reader,inlineReader:reader,progress:{_ in})
        XCTAssertEqual(selected.files,0);XCTAssertEqual(selected.excluded,4)
        let all=WindowsTreeBuilder.scan(root:"C:\\scope",control:ScanControl(),policy:WindowsScanPolicy(workers:4),boundedReader:reader,inlineReader:reader,includeMountedVolumes:true,rootVolume:"root",progress:{_ in})
        XCTAssertEqual(all.files,1);XCTAssertEqual(all.excluded,3);XCTAssertEqual(all.nodes[0].logical,7)
    }

    func testWindowsPathStrategySeparatesNativePrefixFromPublicSpelling() {
        XCTAssertEqual(WindowsPath.nativeSpelling("C:/folder/name"),"\\\\?\\C:\\folder\\name")
        XCTAssertEqual(WindowsPath.nativeSpelling("\\\\server\\share\\folder"),"\\\\?\\UNC\\server\\share\\folder")
        XCTAssertEqual(WindowsPath.nativeSpelling("\\\\?\\C:\\folder"),"\\\\?\\C:\\folder")
    }
    private struct InMemoryReader: DirectoryBatchReader {
        func readDirectory(at path: String, control: ScanControl) -> Batch {
            if control.isCancelled { return .cancelled }
            if path == "C:\\strategy" {
                return .listing([NativeEntry(name:"child",directory:true,reparse:false,attributes:16,logical:0,allocated:0,identity:nil)])
            }
            return .listing([NativeEntry(name:"file.bin",directory:false,reparse:false,attributes:0,logical:7,allocated:4096,identity:nil)])
        }
    }
    func testTreeBuilderUsesInjectedReaderInsteadOfWindowsIO() {
        let result = WindowsTreeBuilder.scan(root:"C:\\strategy",control:ScanControl(),policy:WindowsScanPolicy(workers:4),
            boundedReader:InMemoryReader(),inlineReader:InMemoryReader(),progress:{ _ in })
        XCTAssertEqual(result.files,1);XCTAssertEqual(result.folders,2)
        XCTAssertEqual(result.nodes[0].logical,7);XCTAssertEqual(result.nodes[0].allocated,4096)
    }

}
