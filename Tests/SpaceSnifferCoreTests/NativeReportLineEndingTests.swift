import XCTest
@testable import SpaceSnifferCore

final class NativeReportLineEndingTests: XCTestCase {
    func testNativeBinaryModeAndLFCommandGiveIndependentUTF8GoldenBytes() throws {
        let snapshot = ScanSnapshot(rootPath: "/r", nodes: [
            DiskNode(id: 0, parent: nil, path: "/r", name: "r", isDirectory: true, logicalBytes: 1, children: [1]),
            DiskNode(id: 1, parent: 0, path: "/r/한.bin", name: "한.bin", logicalBytes: 1)])
        // UTF8 /r/한.bin then 0A. 0x41c270 opens wb+; &br maps to 0A for a file.
        let golden = Data([0x2f,0x72,0x2f,0xed,0x95,0x9c,0x2e,0x62,0x69,0x6e,0x0a])
        XCTAssertEqual(Data(Report.simpleFileList(snapshot, ids: [0,1], weights: [1,1]).utf8), golden)
        var sink = ArtifactDataSink(); try Report.write(snapshot, ids: [0,1], weights: [1,1], to: &sink)
        XCTAssertEqual(sink.value, golden)
        XCTAssertNotEqual(golden, Data(LegacyArtifactReference.simpleFileList(snapshot, ids: [0,1], weights: [1,1]).utf8))
    }
    func testFilenameCRLFBytesRemainDataAndOnlyTheRecordDelimiterIsLF() throws {
        let name = "line\r\n🙂.txt", path = "/r/line\r\n🙂.txt"
        let snapshot = ScanSnapshot(rootPath: "/r", nodes: [
            DiskNode(id: 0, parent: nil, path: "/r", name: "r", isDirectory: true, logicalBytes: 1, children: [1]),
            DiskNode(id: 1, parent: 0, path: path, name: name, logicalBytes: 1)])
        let golden = Data([0x2f,0x72,0x2f,0x6c,0x69,0x6e,0x65,0x0d,0x0a,0xf0,0x9f,0x99,0x82,0x2e,0x74,0x78,0x74,0x0a])
        XCTAssertEqual(Data(Report.simpleFileList(snapshot, ids: [0,1], weights: [1,1]).utf8), golden)
        var sink = ArtifactDataSink(); try Report.write(snapshot, ids: [0,1], weights: [1,1], to: &sink)
        XCTAssertEqual(sink.value, golden)
    }
}
