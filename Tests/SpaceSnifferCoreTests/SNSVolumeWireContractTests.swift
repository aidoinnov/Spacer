import XCTest
@testable import SpaceSnifferCore

/// Wire assertions use independent little-endian offsets, not the SNS decoder as an encode oracle.
/// Static native evidence: exportHardCoded 0x408a80 / getDriveSize 0x404790.
/// These tests do not exercise the Windows importer.
final class SNSVolumeWireContractTests: XCTestCase {
    private func fixture() -> ScanSnapshot {
        let root = DiskNode(id: 0, parent: nil, path: "/volume", name: "volume", isDirectory: true,
                            logicalBytes: 100, allocatedBytes: 4096, children: [1])
        let child = DiskNode(id: 1, parent: 0, path: "/volume/file", name: "file",
                             logicalBytes: 100, allocatedBytes: 4096)
        var result = ScanSnapshot(rootPath: root.path, nodes: [root, child])
        result.fileCount = 1; result.folderCount = 1
        result.isVolumeRoot = true; result.volumeTotal = 10_000
        return result
    }
    private func u32(_ data: Data, _ offset: Int) -> UInt32 {
        (0..<4).reduce(0) { $0 | UInt32(data[offset + $1]) << ($1 * 8) }
    }
    private func i64(_ data: Data, _ offset: Int) -> Int64 {
        Int64(bitPattern: (0..<8).reduce(UInt64(0)) { $0 | UInt64(data[offset + $1]) << ($1 * 8) })
    }
    private func sizes(_ data: Data) -> (Int64, Int64) {
        let start = 6 + Int(u32(data, 2)) // v4, type, u32 encoded-name length, encoded name.
        return (i64(data, start), i64(data, start + 8))
    }
    func testWholeVolumeWritesCapacityTwiceWhileLeafWeightsRemainObservedBytes() throws {
        let source = fixture()
        let data = try SNSSnapshot.encode(source)
        XCTAssertEqual(data[0], 4); XCTAssertEqual(data[1], 1)
        XCTAssertEqual(sizes(data).0, 10_000); XCTAssertEqual(sizes(data).1, 10_000)
        let restored = try SNSSnapshot.decode(data)
        XCTAssertEqual(restored.volumeTotal, 10_000)
        XCTAssertEqual(restored.nodes[0].logicalBytes, 10_000)
        XCTAssertEqual(restored.nodes[0].allocatedBytes, 10_000)
        XCTAssertEqual(try ScanFilter("").weights(in: restored, mode: .allocated)[0], 4096)
        XCTAssertEqual(source.nodes[0].logicalBytes, 100)
        XCTAssertEqual(source.nodes[0].allocatedBytes, 4096)
    }
    func testFolderAndUnknownCapacityPreserveRecordedByteFields() throws {
        var folder = fixture(); folder.isVolumeRoot = false
        let folderData = try SNSSnapshot.encode(folder)
        XCTAssertEqual(folderData[1], 3)
        XCTAssertEqual(sizes(folderData).0, 100); XCTAssertEqual(sizes(folderData).1, 4096)
        var typedFolder = fixture(); typedFolder.nodes[0].nativeType = 3
        let typedData = try SNSSnapshot.encode(typedFolder)
        XCTAssertEqual(typedData[1], 3)
        XCTAssertEqual(sizes(typedData).0, 100); XCTAssertEqual(sizes(typedData).1, 4096)
        var unknown = fixture(); unknown.volumeTotal = 0
        let data = try SNSSnapshot.encode(unknown)
        XCTAssertEqual(data[1], 1)
        XCTAssertEqual(sizes(data).0, 100); XCTAssertEqual(sizes(data).1, 4096)
    }
    func testExplicitOfflineDriveOutsideVolumeScopePreservesRawFields() throws {
        var source = fixture(); source.isVolumeRoot = false; source.nodes[0].nativeType = 1
        let data = try SNSSnapshot.encode(source)
        XCTAssertEqual(data[1], 1)
        XCTAssertEqual(sizes(data).0, 100); XCTAssertEqual(sizes(data).1, 4096)
    }
    func testSubtreeExportCannotBorrowOuterVolumeCapacity() throws {
        var source = fixture()
        source.nodes[1].isDirectory = true; source.nodes[1].nativeType = 1
        let data = try SNSSnapshot.encode(source, root: 1)
        XCTAssertEqual(data[1], 1)
        XCTAssertEqual(sizes(data).0, 100); XCTAssertEqual(sizes(data).1, 4096)
    }
    func testIndependentDriveWireInputPreservesStoredTotalsWithoutChildAddition() throws {
        // Produce a native v4 drive record independently: Base64(UTF16LE("/")) = LwA=.
        // It deliberately records 10000/10000 with a 100/4096 child.
        func record(_ kind: UInt8, _ name: [UInt8], _ logical: Int64, _ physical: Int64) -> Data {
            var data = Data([4, kind])
            func append<T: FixedWidthInteger>(_ value: T) {
                var little = value.littleEndian
                withUnsafeBytes(of: &little) { data.append(contentsOf: $0) }
            }
            append(UInt32(name.count)); data.append(contentsOf: name)
            append(logical); append(physical); append(UInt32(kind == 1 ? 16 : 0))
            append(UInt64(0)); append(UInt64(0)); append(UInt64(0)); data.append(contentsOf: [0, 0])
            return data
        }
        var bytes = record(1, Array("LwA=".utf8), 10_000, 10_000)
        bytes.append(record(2, Array("YQA=".utf8), 100, 4096))
        bytes.append(contentsOf: [1, 0, 1, 0])
        let decoded = try SNSSnapshot.decode(bytes)
        XCTAssertEqual(decoded.volumeTotal, 10_000)
        XCTAssertEqual(decoded.nodes[0].logicalBytes, 10_000)
        XCTAssertEqual(decoded.nodes[0].allocatedBytes, 10_000)
        XCTAssertEqual(try ScanFilter("").weights(in: decoded, mode: .allocated)[0], 4096)
    }
}

extension SNSVolumeWireContractTests {
    func testVolumeCapacityMayBeSmallerThanObservedDescendantAllocation() throws {
        // Native drive fields are capacity, not an aggregate constraint. APFS
        // shared extents/clones can make per-file accounting exceed capacity.
        var source=fixture()
        source.nodes[0].logicalBytes=12_000;source.nodes[0].allocatedBytes=16_000
        source.nodes[1].logicalBytes=12_000;source.nodes[1].allocatedBytes=16_000
        let encoded=try SNSSnapshot.encode(source)
        XCTAssertEqual(sizes(encoded).0,10_000);XCTAssertEqual(sizes(encoded).1,10_000)
        let restored=try SNSSnapshot.decode(encoded)
        XCTAssertEqual(restored.volumeTotal,10_000)
        XCTAssertEqual(restored.nodes[0].allocatedBytes,10_000)
        XCTAssertEqual(restored.nodes[1].allocatedBytes,16_000)
        XCTAssertEqual(try ScanFilter("").weights(in:restored,mode:.allocated)[0],16_000)
        XCTAssertEqual(try SNSSnapshot.encode(restored),encoded)
    }
    func testFolderAggregateAndTransitiveLeafOverflowRemainInvalid() throws {
        var folder=fixture();folder.isVolumeRoot=false;folder.nodes[0].logicalBytes=99
        XCTAssertThrowsError(try SNSSnapshot.decode(SNSSnapshot.encode(folder)))
        var root=DiskNode(id:0,parent:nil,path:"/",name:"/",isDirectory:true,logicalBytes:1,allocatedBytes:1,children:[1,3]);root.nativeType=1
        var first=DiskNode(id:1,parent:0,path:"/a",name:"a",isDirectory:true,logicalBytes:0,allocatedBytes:0,children:[2]);first.nativeType=1
        var second=DiskNode(id:3,parent:0,path:"/b",name:"b",isDirectory:true,logicalBytes:0,allocatedBytes:0,children:[4]);second.nativeType=1
        var overflow=ScanSnapshot(rootPath:"/",nodes:[root,first,DiskNode(id:2,parent:1,path:"/a/f",name:"f",logicalBytes:.max,allocatedBytes:.max),second,DiskNode(id:4,parent:3,path:"/b/f",name:"f",logicalBytes:1,allocatedBytes:1)])
        overflow.fileCount=2;overflow.folderCount=3
        XCTAssertThrowsError(try overflow.validated())
    }
}
