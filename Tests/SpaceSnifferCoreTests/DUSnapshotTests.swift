import XCTest
@testable import SpaceSnifferCore

final class DUSnapshotTests: XCTestCase {
    // Synthetic bytes specified independently from the native parser branches, not captured du.exe output.
    func testParentFirstResidualIsSubtractedAndRemoved() throws {
        let bytes = Data("10 C:\\parent\r\n4 C:\\parent\\a\r\n6 C:\\parent\\b\r\n".utf8)
        let s = try DUSnapshot.decode(bytes)
        XCTAssertEqual(s.rootPath, "C:\\")
        XCTAssertFalse(s.isVolumeRoot); XCTAssertEqual(s.volumeTotal, 0)
        XCTAssertEqual(s.fileCount, 0); XCTAssertEqual(s.folderCount, 4)
        XCTAssertEqual(s.nodes[0].logicalBytes, 10_240)
        XCTAssertEqual(s.nodes.filter { $0.nativeType == 6 }.map(\.logicalBytes), [4096, 6144])
        XCTAssertFalse(s.nodes.contains { $0.path == "C:\\parent\\Files" })
        XCTAssertEqual(try ScanFilter("").weights(in: s, mode: .allocated)[0], 10_240)
        XCTAssertEqual(s.nodes.map(\.id), Array(s.nodes.indices))
    }
    func testChildFirstParentFillsOnlyDifferenceAndLowerRepeatDoesNothing() throws {
        let s = try DUSnapshot.decode(Data("4 C:\\parent\\a\n6 C:\\parent\\b\n12 C:\\parent\n8 C:\\parent\n".utf8))
        XCTAssertEqual(s.nodes[0].allocatedBytes, 12_288)
        XCTAssertEqual(s.nodes.filter { $0.nativeType == 6 }.map(\.allocatedBytes), [4096, 6144, 2048])
        XCTAssertEqual(try ScanFilter("").weights(in: s, mode: .logical)[0], 12_288)
    }
    func testDotGroupingKiBSpacesAndDriveRootRecord() throws {
        let s = try DUSnapshot.decode(Data("1.024   c:\\folder with spaces\n".utf8))
        XCTAssertEqual(s.rootPath, "c:\\")
        XCTAssertEqual(s.nodes[1].name, "folder with spaces")
        XCTAssertEqual(s.nodes[0].logicalBytes, 1_048_576)
        let drive = try DUSnapshot.decode(Data("2 C:\\\n".utf8))
        XCTAssertEqual(drive.nodes[0].logicalBytes, 2048)
        XCTAssertEqual(drive.nodes[0].nativeType, 3)
    }
    func testMultipleDriveSelectionAndNativeFilenameAcceptance() throws {
        let data = Data("1 C:\\one\n2 D:\\two\n".utf8)
        XCTAssertEqual(try DUSnapshot.decodeAll(data).map(\.rootPath), ["C:\\", "D:\\"])
        XCTAssertThrowsError(try DUSnapshot.decode(data))
        XCTAssertEqual(try DUSnapshot.decode(data, rootIndex: 1).nodes[0].logicalBytes, 2048)
        XCTAssertThrowsError(try DUSnapshot.decode(data, rootIndex: -1))
        XCTAssertTrue(DUSnapshot.accepts(filename: "tree.Du"))
        XCTAssertFalse(DUSnapshot.accepts(filename: ".du"))
        XCTAssertFalse(DUSnapshot.accepts(filename: "tree.du.csv"))
    }
    func testExplicitWindowsCodePageIsRequiredForHighBytes() throws {
        var bytes = Data("1 C:\\caf".utf8); bytes.append(0xe9); bytes.append(10)
        XCTAssertThrowsError(try DUSnapshot.decode(bytes))
        XCTAssertEqual(try DUSnapshot.decode(bytes, legacyCodePage: 1252).nodes[1].name, "café")
    }
    func testMalformedUnsupportedAndOverflowInputFailsWithoutPartialResult() {
        for text in ["", "Size Path\n", "1\tC:\\x\n", "1..2 C:\\x\n", "-1 C:\\x\n", "1x C:\\x\n",
                     "1 /tmp\n", "1 C:x\n", "1 C:\\a\\..\\b\n", "1 C:\\a\\\\b\n", "1 \\\\host\\share\n",
                     "1 \"C:\\x\"\n", "9007199254740992 C:\\x\n", "999999999999999999999999 C:\\x\n",
                     "1 C:\\p\n2 C:\\p\\child\n", "1 C:\\p\n2 C:\\p\n", "1 C:\\p\n\n2 C:\\q\n"] {
            XCTAssertThrowsError(try DUSnapshot.decode(Data(text.utf8)), text)
        }
        XCTAssertThrowsError(try DUSnapshot.decode(Data([49,32,67,58,92,0,10])))
    }
    func testLookupUsesExactUTF16WithoutCaseOrCanonicalMerging() throws {
        let s = try DUSnapshot.decode(Data("1 C:\\é\n2 C:\\e\u{301}\n3 C:\\A\n4 C:\\a\n".utf8), legacyCodePage: 65001)
        let names = s.nodes.filter { $0.isDirectory && $0.parent == 0 }.map { Array($0.name.utf16) }
        XCTAssertEqual(names, [[0x00e9], [0x0065, 0x0301], [0x0041], [0x0061]])
        XCTAssertEqual(s.nodes[0].logicalBytes, 10_240)
        _ = try s.validated()
        let roots = try DUSnapshot.decodeAll(Data("1 c:\\x\n2 C:\\x\n".utf8))
        XCTAssertEqual(roots.map(\.rootPath), ["c:\\", "C:\\"])
    }
    func testPreCancelledControlAndTaskThrowWithoutResult() async throws {
        let bytes = Data("1 C:\\x\n".utf8)
        let control = ScanControl(); control.cancel()
        XCTAssertThrowsError(try DUSnapshot.decode(bytes, control: control)) { XCTAssertTrue($0 is CancellationError) }
        try await Task {
            withUnsafeCurrentTask { $0?.cancel() }
            XCTAssertThrowsError(try DUSnapshot.decode(bytes)) { XCTAssertTrue($0 is CancellationError) }
        }.value
    }
    func testExplicitResourceBoundsFail() {
        let data = Data("1 C:\\parent\\child\n".utf8)
        XCTAssertThrowsError(try DUSnapshot.decode(data, limits: .init(maximumBytes: 1)))
        XCTAssertThrowsError(try DUSnapshot.decode(data, limits: .init(maximumNodes: 1)))
        XCTAssertThrowsError(try DUSnapshot.decode(data, limits: .init(maximumDepth: 1)))
        XCTAssertThrowsError(try DUSnapshot.decode(Data("1 C:\\a\n1 C:\\b\n".utf8), limits: .init(maximumRecords: 1)))
    }
}
