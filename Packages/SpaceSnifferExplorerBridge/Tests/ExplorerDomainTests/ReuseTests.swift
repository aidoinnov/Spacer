import XCTest
@testable import ExplorerDomain
final class ReuseTests:XCTestCase{
 func testNativeSNSAndFilterAreShared() throws{
  var s=ScanSnapshot(rootPath:"/fixture");s.nodes.append(DiskNode(id:0,parent:nil,path:"/fixture",name:"fixture",isDirectory:true,logicalBytes:100,allocatedBytes:4096,children:[1]));s.nodes.append(DiskNode(id:1,parent:0,path:"/fixture/a.zip",name:"a.zip",logicalBytes:100,allocatedBytes:4096));s.filesForTest()
  let bytes=try SNSSnapshot.encode(s);let reopened=try SNSSnapshot.decode(bytes);XCTAssertEqual(reopened.nodes[1].name,"a.zip");XCTAssertEqual(try ScanFilter("*.zip;>4kb").weights(in:reopened,mode:.allocated)[0],4096)
 }
}
private extension ScanSnapshot{mutating func filesForTest(){fileCount=1;folderCount=1}}

extension ReuseTests {
    func testExplicitLegacyKoreanDecoding() throws {
        let bytes = Data([0xc7,0xd1,0xb1,0xdb]) // CP949 한글
        XCTAssertThrowsError(try WindowsLegacyText.decode(bytes, codePage:nil))
        XCTAssertEqual(try WindowsLegacyText.decode(bytes, codePage:949),"한글")
        XCTAssertThrowsError(try WindowsLegacyText.decode(bytes, codePage:UInt32.max))
    }
    func testMultiRootRequiresChoiceAndPreservesTagMasks() throws {
        var snapshot=ScanSnapshot(rootPath:"C:\\data",nodes:[DiskNode(id:0,parent:nil,path:"C:\\data",name:"data",isDirectory:true,logicalBytes:8,allocatedBytes:4096,children:[1]),DiskNode(id:1,parent:0,path:"C:\\data\\한글.zip",name:"한글.zip",logicalBytes:8,allocatedBytes:4096)])
        snapshot.fileCount=1;snapshot.folderCount=1;snapshot.tags=["C:\\data":12]
        let encoded=try SNSSnapshot.encode(roots:[snapshot,snapshot])
        XCTAssertThrowsError(try SNSSnapshot.decode(encoded))
        let restored=try SNSSnapshot.decode(encoded,rootIndex:1)
        XCTAssertEqual(restored.tags,snapshot.tags)
        XCTAssertEqual(try ScanFilter("*한글*").weights(in:restored,mode:.logical)[0],8)
        XCTAssertEqual(try ScanFilter(":green").weights(in:restored,mode:.logical)[0],8)
        XCTAssertEqual(try ScanFilter(":blue").weights(in:restored,mode:.logical)[0],8)
        XCTAssertEqual(try ScanFilter(":red").weights(in:restored,mode:.logical)[0],0)
    }
}

extension ReuseTests {
    func testNativeDriveCapacityDoesNotLimitFileAccounting() throws {
        var source=ScanSnapshot(rootPath:"C:\\data",nodes:[DiskNode(id:0,parent:nil,path:"C:\\data",name:"data",isDirectory:true,logicalBytes:9,allocatedBytes:9,children:[1]),DiskNode(id:1,parent:0,path:"C:\\data\\f",name:"f",logicalBytes:9,allocatedBytes:9)])
        source.fileCount=1;source.folderCount=1;source.isVolumeRoot=true;source.volumeTotal=5
        let reopened=try SNSSnapshot.decode(SNSSnapshot.encode(source))
        XCTAssertEqual(reopened.volumeTotal,5)
        XCTAssertEqual(try ScanFilter("").weights(in:reopened,mode:.allocated)[0],9)
    }
}

extension ReuseTests {
    func testConfiguredExportSharesNativeTemplateSelectionAndRejectsUnrelatedXML() throws {
        let config=NativeConfiguration.ExportConfiguration(description:"경로와 크기",detail:"{if{<%isfile%>}=={true}?{<%pathfile%>\t<%disksizebytes%>{&br}}}",blockSorting:"files",fineSorting:"size",direction:"desc")
        let xml=try NativeConfiguration(exportConfigurations:[config]).encodedXML()
        XCTAssertEqual(try ExplorerSemantics.exportConfigurations(xml,codePage:65001),[config])
        XCTAssertEqual(try ExplorerSemantics.exportConfigurations(config.encodedXML(),codePage:65001),[config])
        XCTAssertThrowsError(try ExplorerSemantics.exportConfigurations(Data("<unrelated/>".utf8)))
        XCTAssertThrowsError(try ExplorerSemantics.exportConfigurations(NativeConfiguration().encodedXML()))
        let root=DiskNode(id:0,parent:nil,path:"/r",name:"r",isDirectory:true,logicalBytes:7,allocatedBytes:9,children:[1])
        let file=DiskNode(id:1,parent:0,path:"/r/f",name:"f",isDirectory:false,logicalBytes:7,allocatedBytes:9)
        let snapshot=ScanSnapshot(rootPath:"/r",nodes:[root,file]);var sink=ConfiguredTestSink()
        try ExplorerSemantics.configuredReport(snapshot,xml:xml,index:0,text:"",mode:.allocated,hidden:true,root:0,codePage:65001,to:&sink)
        XCTAssertEqual(String(decoding:sink.bytes,as:UTF8.self),"/r/f\t9\n")
        XCTAssertThrowsError(try ExplorerSemantics.configuredReport(snapshot,xml:xml,index:1,text:"",mode:.allocated,hidden:true,root:0,codePage:65001,to:&sink))
    }
}

private struct ConfiguredTestSink: ArtifactByteSink { var bytes=[UInt8]();mutating func append(_ raw:UnsafeRawBufferPointer)throws {bytes.append(contentsOf:raw)} }
